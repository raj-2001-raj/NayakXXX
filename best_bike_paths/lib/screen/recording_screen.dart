import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/sensor_service.dart';
import '../services/navigation_service.dart';
import 'manual_report_dialog.dart';
import 'ride_summary_screen.dart';
import 'app_bottom_nav.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

class PotholeReport {
  final LatLng location;
  final bool isManual;
  final String category;
  bool isVerified;

  PotholeReport({
    required this.location,
    required this.isManual,
    required this.category,
    this.isVerified = true,
  });
}

class RouteRecommendation {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final int reportedIssues;
  final double severityScore;
  final double cobblestoneScore;

  const RouteRecommendation({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.reportedIssues,
    required this.severityScore,
    required this.cobblestoneScore,
  });
}

class AnomalyPoint {
  final LatLng location;
  final double weight;

  const AnomalyPoint({required this.location, required this.weight});
}

class FountainPoint {
  final String id;
  final LatLng location;

  const FountainPoint({required this.id, required this.location});
}

class SurfacePoint {
  final LatLng location;
  final double weight;

  const SurfacePoint({required this.location, required this.weight});
}

class SurfaceData {
  final List<SurfacePoint> points;
  final List<List<LatLng>> segments;

  const SurfaceData({required this.points, required this.segments});
}

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
  with WidgetsBindingObserver {
  final SensorService _sensorService = SensorService();
  final NavigationService _navService = NavigationService();
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;
  StreamSubscription<Position>? _positionSub;
  LatLng _currentLocation = const LatLng(45.4642, 9.1900);
  LatLng? _startLocation;
  LatLng? _destinationPoint;
  double _currentSpeedMps = 0;

  bool _isRideActive = false;

  List<Map<String, dynamic>> _searchResults = [];
  bool _showResults = false;

  List<LatLng> _routePoints = [];
  final List<LatLng> _ridePath = [];
  bool _hasRoute = false;
  List<RouteRecommendation> _routeOptions = [];
  int _selectedRouteIndex = 0;
  bool _loadingRoutes = false;
  String? _routeError;
  bool _autoSelectedRoute = false;
  bool _avoidCobblestones = false;
  bool _showFountains = true;
  bool _loadingAmenities = false;
  Map<String, double> _debugStats = {};
  bool _testMode = false;
  bool _pendingAutoEndDialog = false;
  bool _autoEndDismissed = false;
  bool _restoringRide = false;

  List<FountainPoint> _fountains = [];
  List<SurfacePoint> _surfacePoints = [];
  List<List<LatLng>> _surfaceSegments = [];

  final List<PotholeReport> _sessionReports = [];
  DateTime? _rideStartTime;
  String? _activeRideId;
  int _tileErrorCount = 0;
  String? _tileErrorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeLocation();
    _loadPreferencesAndData();
    _restoreRideIfNeeded();
  }

  void _startLocationStream() {
    _positionSub?.cancel();
    final settings = _buildLocationSettings();
    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      _onPositionUpdate,
    );
  }

  void _onPositionUpdate(Position pos) {
    final loc = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _currentLocation = loc;
      if (_isRideActive) {
        _ridePath.add(loc);
      }
      _currentSpeedMps = pos.speed;
    });
    _sensorService.updateSpeed(_currentSpeedMps);
    if (_isRideActive) {
      _checkDestinationArrival(loc);
    }
  }

  void _checkDestinationArrival(LatLng location) {
    final destination = _destinationPoint;
    if (destination == null) return;
    final meters = const Distance().as(
      LengthUnit.Meter,
      destination,
      location,
    );
    if (_autoEndDismissed && meters > 120) {
      _autoEndDismissed = false;
    }
    if (meters <= 60 && !_pendingAutoEndDialog && !_autoEndDismissed) {
      _pendingAutoEndDialog = true;
      if (mounted) {
        _showAutoEndDialog();
      }
    }
  }

  Future<void> _showAutoEndDialog() async {
    if (!_isRideActive || !mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Destination reached'),
        content: const Text('You are near your destination. End the ride now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep riding'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End ride'),
          ),
        ],
      ),
    );
    _pendingAutoEndDialog = false;
    if (result == true) {
      await _stopRide();
    } else {
      _autoEndDismissed = true;
    }
  }

  Future<void> _persistRideState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ride_active', _isRideActive);
    if (_isRideActive) {
      await prefs.setString('ride_id', _activeRideId ?? '');
      await prefs.setDouble('start_lat', _startLocation?.latitude ?? 0);
      await prefs.setDouble('start_lon', _startLocation?.longitude ?? 0);
      await prefs.setDouble('dest_lat', _destinationPoint?.latitude ?? 0);
      await prefs.setDouble('dest_lon', _destinationPoint?.longitude ?? 0);
      await prefs.setString(
        'ride_start_time',
        _rideStartTime?.toIso8601String() ?? '',
      );
    }
  }

  Future<void> _clearRideState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ride_active');
    await prefs.remove('ride_id');
    await prefs.remove('start_lat');
    await prefs.remove('start_lon');
    await prefs.remove('dest_lat');
    await prefs.remove('dest_lon');
    await prefs.remove('ride_start_time');
  }

  Future<bool> _ensureSensorConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getBool('sensor_consent');
    if (existing == true) return true;

    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Motion sensor access'),
        content: const Text(
          'We use your phone’s motion sensors (accelerometer and gyroscope) to detect bumps and potholes during rides. Do you want to allow this?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    final allowed = result == true;
    await prefs.setBool('sensor_consent', allowed);
    if (!allowed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sensor access is required for pothole detection.'),
        ),
      );
    }
    return allowed;
  }

  Future<void> _restoreRideIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getBool('ride_active') ?? false;
    if (!active) return;

    final startLat = prefs.getDouble('start_lat') ?? 0;
    final startLon = prefs.getDouble('start_lon') ?? 0;
    final destLat = prefs.getDouble('dest_lat') ?? 0;
    final destLon = prefs.getDouble('dest_lon') ?? 0;
    final rideId = prefs.getString('ride_id');
    final startTimeRaw = prefs.getString('ride_start_time');

    _restoringRide = true;
    _startLocation = LatLng(startLat, startLon);
    _destinationPoint = destLat != 0 || destLon != 0
        ? LatLng(destLat, destLon)
        : null;
    _activeRideId = (rideId?.isNotEmpty ?? false) ? rideId : null;
    _rideStartTime =
        startTimeRaw != null && startTimeRaw.isNotEmpty
            ? DateTime.tryParse(startTimeRaw)
            : null;
    setState(() {
      _isRideActive = true;
      _pendingAutoEndDialog = false;
      _autoEndDismissed = false;
    });
    await _resumeActiveRide();
  }

  Future<void> _resumeActiveRide() async {
    final consented = await _ensureSensorConsent();
    if (!consented) return;
    final ready = await _ensureLocationReady();
    if (!ready) return;
    final position = await Geolocator.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
      _currentSpeedMps = position.speed;
    });
    _sensorService.updateSpeed(_currentSpeedMps);

    _sensorService.startListening(
      () => _reportPothole(isManual: false),
      onDebug: (data) {
        if (!mounted) return;
        setState(() => _debugStats = data);
      },
    );
    _sensorService.setTestMode(_testMode);
    _startLocationStream();

    if (_destinationPoint != null) {
      final options = await _navService.getBikeRoutes(
        _currentLocation,
        _destinationPoint!,
      );
      if (!mounted) return;
      final withIssues = await _attachIssueCounts(options);
      final bestIndex = _pickBestRouteIndex(withIssues);
      setState(() {
        _routeOptions = withIssues;
        _selectedRouteIndex = bestIndex;
        _routePoints = withIssues.isNotEmpty
            ? withIssues[bestIndex].points
            : [];
        _hasRoute = withIssues.isNotEmpty;
        _autoSelectedRoute = withIssues.isNotEmpty;
      });
    }

    if (_restoringRide && mounted) {
      _restoringRide = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resumed active ride tracking.')),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ensureLocationReady();
      if (_isRideActive) {
        _startLocationStream();
        if (_pendingAutoEndDialog) {
          _showAutoEndDialog();
        }
      }
    }
  }

  Future<void> _loadPreferencesAndData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _avoidCobblestones = prefs.getBool('avoid_cobblestones') ?? false;
      _showFountains = prefs.getBool('show_fountains') ?? true;
    });
    await _loadAmenitiesData();
  }

  Future<void> _loadAmenitiesData() async {
    setState(() => _loadingAmenities = true);
    if (_showFountains) {
      _fountains = await _fetchFountains();
    } else {
      _fountains = [];
    }

    if (_avoidCobblestones) {
      final surfaceData = await _fetchSurfaceSegments();
      _surfacePoints = surfaceData.points;
      _surfaceSegments = surfaceData.segments;
    } else {
      _surfacePoints = [];
      _surfaceSegments = [];
    }

    if (mounted) {
      setState(() => _loadingAmenities = false);
    }
  }

  Future<void> _initializeLocation() async {
    final ready = await _ensureLocationReady();
    if (!ready) return;
    final Position position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _currentSpeedMps = position.speed;
      });
      _sensorService.updateSpeed(_currentSpeedMps);
      _mapController.move(_currentLocation, 15);
    }
  }

  Future<bool> _ensureLocationReady({bool showSnackBar = true}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Turn on location services to use ride tracking.'),
          ),
        );
      }
      await Geolocator.openLocationSettings();
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required to ride.'),
          ),
        );
      }
      return false;
    }
    if (permission == LocationPermission.deniedForever) {
      if (showSnackBar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission is permanently denied. Enable it in system settings.',
            ),
          ),
        );
      }
      await Geolocator.openAppSettings();
      return false;
    }

    return true;
  }

  LocationSettings _buildLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Ride in progress',
          notificationText: 'Tracking your route in the background.',
          enableWakeLock: true,
          enableWifiLock: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 5,
    );
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.length > 2) {
        final results = await _navService.searchPlaces(query);
        setState(() {
          _searchResults = results;
          _showResults = true;
        });
      } else {
        setState(() => _showResults = false);
      }
    });
  }

  Future<void> _selectDestination(Map<String, dynamic> place) async {
    setState(() {
      _showResults = false;
      _searchController.text = place['display_name'].split(',')[0];
      FocusScope.of(context).unfocus();
      _loadingRoutes = true;
      _routeError = null;
    });

    final destLat = double.parse(place['lat']);
    final destLng = double.parse(place['lon']);
    final destPoint = LatLng(destLat, destLng);
    _destinationPoint = destPoint;
    if (_isRideActive) {
      await _persistRideState();
    }

    final options = await _navService.getBikeRoutes(
      _currentLocation,
      destPoint,
    );

    final withIssues = await _attachIssueCounts(options);
    final bestIndex = _pickBestRouteIndex(withIssues);

    if (mounted) {
      setState(() {
        _routeOptions = withIssues;
        _selectedRouteIndex = bestIndex;
        _routePoints = withIssues.isNotEmpty
            ? withIssues[bestIndex].points
            : [];
        _hasRoute = withIssues.isNotEmpty;
        _loadingRoutes = false;
        _routeError = withIssues.isEmpty
            ? 'No routes available. Try another destination.'
            : null;
        _autoSelectedRoute = withIssues.isNotEmpty;
      });

      if (_routeOptions.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([_currentLocation, destPoint]),
            padding: const EdgeInsets.all(50),
          ),
        );
        _showRouteOptionsSheet();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Auto-selected Route ${bestIndex + 1}. You can change it below.',
            ),
          ),
        );
      }
    }
  }

  int _pickBestRouteIndex(List<RouteRecommendation> options) {
    if (options.isEmpty) return 0;
    double bestScore = double.infinity;
    int bestIndex = 0;
    for (int i = 0; i < options.length; i++) {
      final option = options[i];
      final minutes = option.durationSeconds / 60;
      final cobblePenalty = _avoidCobblestones ? option.cobblestoneScore * 2 : 0;
      final score = minutes + (option.severityScore * 2) + cobblePenalty;
      if (score < bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  Future<List<RouteRecommendation>> _attachIssueCounts(
    List<BikeRouteOption> options,
  ) async {
    if (options.isEmpty) return [];

    final anomalies = await _fetchAnomalyPoints();
    final distance = const Distance();
    final surfacePoints = _avoidCobblestones ? _surfacePoints : <SurfacePoint>[];

    return options.map((option) {
      final sampled = _sampleRoutePoints(option.points, maxPoints: 200);
      int count = 0;
      double severityScore = 0;
      double cobbleScore = 0;
      for (final anomaly in anomalies) {
        for (final point in sampled) {
          final meters = distance.as(LengthUnit.Meter, anomaly.location, point);
          if (meters <= 50) {
            count++;
            severityScore += anomaly.weight;
            break;
          }
        }
      }

      if (surfacePoints.isNotEmpty) {
        for (final surface in surfacePoints) {
          for (final point in sampled) {
            final meters = distance.as(LengthUnit.Meter, surface.location, point);
            if (meters <= 40) {
              cobbleScore += surface.weight;
              break;
            }
          }
        }
      }
      return RouteRecommendation(
        points: option.points,
        distanceMeters: option.distanceMeters,
        durationSeconds: option.durationSeconds,
        reportedIssues: count,
        severityScore: severityScore,
        cobblestoneScore: cobbleScore,
      );
    }).toList();
  }

  Future<List<AnomalyPoint>> _fetchAnomalyPoints() async {
    try {
      final rows = await Supabase.instance.client
          .from('anomalies')
          .select('location,severity')
          .limit(500) as List<dynamic>;

      return rows
          .map((row) => _parseAnomalyPoint(row))
          .whereType<AnomalyPoint>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  AnomalyPoint? _parseAnomalyPoint(Map<String, dynamic> row) {
    final location = _parseGeoPoint(row['location']);
    if (location == null) return null;
    final severity = row['severity']?.toString();
    return AnomalyPoint(location: location, weight: _severityWeight(severity));
  }

  double _severityWeight(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'critical':
        return 5;
      case 'high':
        return 4;
      case 'medium':
        return 2;
      case 'low':
        return 1;
      default:
        return 1;
    }
  }

  LatLng? _parseGeoPoint(dynamic location) {
    if (location == null) return null;
    if (location is Map<String, dynamic>) {
      final coords = location['coordinates'];
      if (coords is List && coords.length >= 2) {
        return LatLng(
          (coords[1] as num).toDouble(),
          (coords[0] as num).toDouble(),
        );
      }
    }
    if (location is List && location.length >= 2) {
      return LatLng(
        (location[1] as num).toDouble(),
        (location[0] as num).toDouble(),
      );
    }
    if (location is String) {
      final match = RegExp(r'POINT\(([-\d\.]+)\s+([-\d\.]+)\)').firstMatch(
        location,
      );
      if (match != null) {
        final lon = double.tryParse(match.group(1)!);
        final lat = double.tryParse(match.group(2)!);
        if (lat != null && lon != null) return LatLng(lat, lon);
      }
    }
    return null;
  }

  Future<List<FountainPoint>> _fetchFountains() async {
    try {
      final rows = await Supabase.instance.client
          .from('fountains')
          .select('osm_id,location')
          .limit(1200) as List<dynamic>;

      return rows
          .map((row) {
            final location = _parseGeoPoint(row['location']);
            if (location == null) return null;
            return FountainPoint(
              id: row['osm_id']?.toString() ?? '-',
              location: location,
            );
          })
          .whereType<FountainPoint>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _routeToNearestFountain() async {
    final ready = await _ensureLocationReady();
    if (!ready) return;

    setState(() {
      _showResults = false;
      _loadingRoutes = true;
      _routeError = null;
    });

    final position = await Geolocator.getCurrentPosition();
    final current = LatLng(position.latitude, position.longitude);
    _currentLocation = current;

    var fountains = _fountains;
    if (fountains.isEmpty) {
      fountains = await _fetchFountains();
      _fountains = fountains;
    }

    if (fountains.isEmpty) {
      if (mounted) {
        setState(() => _loadingRoutes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No fountains available nearby.')),
        );
      }
      return;
    }

    final distance = const Distance();
    FountainPoint nearest = fountains.first;
    double nearestMeters =
        distance.as(LengthUnit.Meter, current, fountains.first.location);
    for (final fountain in fountains.skip(1)) {
      final meters =
          distance.as(LengthUnit.Meter, current, fountain.location);
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearest = fountain;
      }
    }

    _destinationPoint = nearest.location;
    _searchController.text = 'Nearest fountain';

    final options = await _navService.getBikeRoutes(
      current,
      nearest.location,
    );

    final withIssues = await _attachIssueCounts(options);
    final bestIndex = _pickBestRouteIndex(withIssues);

    if (mounted) {
      setState(() {
        _routeOptions = withIssues;
        _selectedRouteIndex = bestIndex;
        _routePoints = withIssues.isNotEmpty
            ? withIssues[bestIndex].points
            : [];
        _hasRoute = withIssues.isNotEmpty;
        _loadingRoutes = false;
        _routeError = withIssues.isEmpty
            ? 'No routes available. Try again.'
            : null;
        _autoSelectedRoute = withIssues.isNotEmpty;
      });

      if (_routeOptions.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([current, nearest.location]),
            padding: const EdgeInsets.all(50),
          ),
        );
        _showRouteOptionsSheet();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Routing to the nearest fountain.'),
          ),
        );
      }
    }
  }

  Future<SurfaceData> _fetchSurfaceSegments() async {
    try {
      final rows = await Supabase.instance.client
          .from('surface_segments')
          .select('surface,centroid,geometry')
          .limit(1500) as List<dynamic>;

      final points = <SurfacePoint>[];
      final segments = <List<LatLng>>[];

      for (final row in rows) {
        final surface = row['surface']?.toString();
        final centroid = _parseGeoPoint(row['centroid']);
        if (centroid != null) {
          points.add(
            SurfacePoint(
              location: centroid,
              weight: _surfaceWeight(surface),
            ),
          );
        }

        final geometry = row['geometry'];
        final parsed = _parseSurfaceGeometry(geometry);
        if (parsed.isNotEmpty) {
          segments.add(parsed);
        }
      }

      return SurfaceData(points: points, segments: segments);
    } catch (_) {
      return const SurfaceData(points: [], segments: []);
    }
  }

  double _surfaceWeight(String? surface) {
    switch (surface?.toLowerCase()) {
      case 'cobblestone':
      case 'sett':
      case 'unhewn_cobblestone':
        return 3;
      case 'paving_stones':
      case 'setts':
        return 2;
      default:
        return 1;
    }
  }

  List<LatLng> _parseSurfaceGeometry(dynamic geometry) {
    if (geometry is Map<String, dynamic>) {
      final type = geometry['type'];
      final coords = geometry['coordinates'];
      if (type == 'LineString' && coords is List) {
        return coords
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
      }
      if (type == 'Polygon' && coords is List && coords.isNotEmpty) {
        final ring = coords.first as List;
        return ring
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
      }
      if (type == 'MultiLineString' && coords is List && coords.isNotEmpty) {
        final first = coords.first as List;
        return first
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
      }
    }
    return [];
  }

  List<LatLng> _sampleRoutePoints(
    List<LatLng> points, {
    int maxPoints = 200,
  }) {
    if (points.length <= maxPoints) return points;
    final step = (points.length / maxPoints).ceil().clamp(1, points.length);
    final sampled = <LatLng>[];
    for (int i = 0; i < points.length; i += step) {
      sampled.add(points[i]);
    }
    return sampled;
  }

  void _showRouteOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recommended Bike Routes',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                ..._routeOptions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final option = entry.value;
                  final selected = index == _selectedRouteIndex;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedRouteIndex = index;
                        _routePoints = option.points;
                        _autoSelectedRoute = false;
                      });
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF00FF00).withOpacity(0.15)
                            : const Color(0xFF2C2C2C),
                        borderRadius: BorderRadius.circular(12),
                        border: selected
                            ? Border.all(color: const Color(0xFF00FF00))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.alt_route,
                            color: selected
                                ? const Color(0xFF00FF00)
                                : Colors.white,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Route ${index + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_formatDuration(option.durationSeconds)} • ${_formatDistance(option.distanceMeters)}',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Reported issues: ${option.reportedIssues} • Severity: ${option.severityScore.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                                if (_avoidCobblestones)
                                  Text(
                                    'Cobblestones score: ${option.cobblestoneScore.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: Colors.orangeAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return '${hours}h ${remaining}m';
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toStringAsFixed(0)} m';
  }

  Future<void> _startRide() async {
    // Prevent duplicate ride creation
    if (_isRideActive || _activeRideId != null) {
      debugPrint('[RIDE] Ride already active, ignoring start request');
      return;
    }

    final consented = await _ensureSensorConsent();
    if (!consented) return;
    final ready = await _ensureLocationReady();
    if (!ready) return;
    if (!_hasRoute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination first!')),
      );
      return;
    }

    if (_destinationPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Destination missing. Please reselect.')),
      );
      return;
    }

    final position = await Geolocator.getCurrentPosition();
    final startLoc = LatLng(position.latitude, position.longitude);
    _currentSpeedMps = position.speed;
    _sensorService.updateSpeed(_currentSpeedMps);

    String? rideId;
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        // Only insert columns that exist in the rides table
        final ride = await Supabase.instance.client
            .from('rides')
            .insert({
              'user_id': userId,
              'start_time': DateTime.now().toIso8601String(),
              'start_lat': startLoc.latitude,
              'start_lon': startLoc.longitude,
            })
            .select('id')
            .single();
        rideId = ride['id']?.toString();
        debugPrint('[RIDE] Started ride with id: $rideId for user: $userId');
      }
    } catch (e) {
      debugPrint('[RIDE] Failed to insert ride: $e');
    }

    setState(() {
      _isRideActive = true;
      _startLocation = startLoc;
      _currentLocation = startLoc;
      _sessionReports.clear();
      _rideStartTime = DateTime.now();
      _ridePath
        ..clear()
        ..add(startLoc);
      _activeRideId = rideId;
      _pendingAutoEndDialog = false;
      _autoEndDismissed = false;
    });
    await _persistRideState();

    _sensorService.startListening(
      () => _reportPothole(isManual: false),
      onDebug: (data) {
        if (!mounted) return;
        setState(() => _debugStats = data);
      },
    );
    _sensorService.setTestMode(_testMode);

    _startLocationStream();
  }

  Future<void> _stopRide() async {
    _sensorService.stopListening();
    _positionSub?.cancel();
    
    // Save ride ID before clearing state
    final rideId = _activeRideId;
    
    setState(() {
      _isRideActive = false;
      _activeRideId = null; // Clear to prevent duplicate operations
    });
    await _clearRideState();
    setState(() => _testMode = false);
    _sensorService.setTestMode(false);

    final rideDuration = DateTime.now().difference(
      _rideStartTime ?? DateTime.now(),
    );

    if (rideId != null) {
      try {
        // Only update end_time - the rides table may not have end_lat/end_lon columns
        await Supabase.instance.client
            .from('rides')
            .update({
              'end_time': DateTime.now().toIso8601String(),
            })
            .eq('id', rideId);
        debugPrint('[RIDE] Stopped ride: $rideId');
      } catch (e) {
        debugPrint('[RIDE] Failed to update ride on stop: $e');
      }
    }

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RideSummaryScreen(
            routePoints: _ridePath.isNotEmpty ? _ridePath : _routePoints,
            reports: _sessionReports,
            startPoint: _startLocation ?? _currentLocation,
            endPoint: _currentLocation,
            rideDuration: rideDuration,
            rideId: rideId,
          ),
        ),
      );
    }
  }

  void _onNavTap(int index) {
    if (index == 1) return;
    final target = _navTarget(index);
    if (target == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => target),
    );
  }

  Widget? _navTarget(int index) {
    switch (index) {
      case 0:
        return const DashboardScreen();
      case 2:
        return const HistoryScreen();
      case 3:
        return const ProfileScreen();
      default:
        return null;
    }
  }

  Future<void> _reportPothole({required bool isManual}) async {
    String category = 'Bump';

    if (isManual) {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => const ManualReportDialog(),
      );
      if (result == null) return;
      category = result;
    }

    final Position position = await Geolocator.getCurrentPosition();
    final potholeLoc = LatLng(position.latitude, position.longitude);

    setState(() {
      _sessionReports.add(
        PotholeReport(
          location: potholeLoc,
          isManual: isManual,
          category: category,
          isVerified: isManual,
        ),
      );
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$category Recorded! Added to Summary.'),
          backgroundColor: isManual ? Colors.orange : Colors.red,
          duration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  void _toggleTestMode() {
    final next = !_testMode;
    setState(() => _testMode = next);
    _sensorService.setTestMode(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'Test mode enabled (looser thresholds).'
                : 'Test mode disabled.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sensorService.stopListening();
    _positionSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.bbp.best_bike_paths',
                errorTileCallback: (tile, error, stackTrace) {
                  if (!mounted) return;
                  setState(() {
                    _tileErrorCount += 1;
                    _tileErrorMessage ??=
                        'Map tiles unavailable. Check emulator internet or DNS.';
                  });
                },
              ),
              if (_surfaceSegments.isNotEmpty)
                PolylineLayer(
                  polylines: _surfaceSegments
                      .map(
                        (segment) => Polyline(
                          points: segment,
                          strokeWidth: 2,
                          color: Colors.orangeAccent.withOpacity(0.6),
                        ),
                      )
                      .toList(),
                ),
              if (_routeOptions.isNotEmpty)
                PolylineLayer(
                  polylines: _routeOptions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final option = entry.value;
                    final selected = index == _selectedRouteIndex;
                    return Polyline(
                      points: option.points,
                      strokeWidth: selected ? 5.0 : 3.0,
                      color: selected
                          ? const Color(0xFF00FF00)
                          : Colors.blueGrey.withOpacity(0.6),
                    );
                  }).toList(),
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.navigation,
                      color: Colors.blue,
                      size: 40,
                    ),
                  ),
                  ..._sessionReports.map(
                    (r) => Marker(
                      point: r.location,
                      width: 30,
                      height: 30,
                      child: Icon(
                        r.isManual ? Icons.report : Icons.warning,
                        color: r.isManual ? Colors.orange : Colors.red,
                        size: 25,
                      ),
                    ),
                  ),
                  ..._fountains.map(
                    (f) => Marker(
                      point: f.location,
                      width: 24,
                      height: 24,
                      child: const Icon(
                        Icons.water_drop,
                        color: Colors.lightBlueAccent,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          if (_debugStats.isNotEmpty)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Z g: ${_debugStats['zForceG']?.toStringAsFixed(2) ?? '-'}'),
                      Text('Raw Z: ${_debugStats['rawZ']?.toStringAsFixed(2) ?? '-'}'),
                      Text('Jerk: ${_debugStats['jerk']?.toStringAsFixed(2) ?? '-'} g/s'),
                      Text('Speed: ${_debugStats['speedKmh']?.toStringAsFixed(1) ?? '-'} km/h'),
                      Text('Thresh: ${_debugStats['threshold']?.toStringAsFixed(2) ?? '-'}'),
                      Text('Conf: ${_debugStats['confidence']?.toStringAsFixed(2) ?? '-'}'),
                    ],
                  ),
                ),
              ),
            ),

          if (!_isRideActive)
            Positioned(
              top: 50,
              left: 20,
              right: 20,
              child: Column(
                children: [
                  Card(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      decoration: const InputDecoration(
                        hintText: 'Search Destination...',
                        prefixIcon: Icon(Icons.search),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(15),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _loadingRoutes
                            ? null
                            : _routeToNearestFountain,
                        icon: const Icon(Icons.water_drop),
                        label: const Text('NEAREST FOUNTAIN'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                  if (_showResults)
                    Container(
                      color: Colors.white,
                      height: 200,
                      child: ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final place = _searchResults[index];
                          return ListTile(
                            title: Text(
                              place['display_name'].split(',')[0],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onTap: () => _selectDestination(place),
                          );
                        },
                      ),
                    ),
                  if (_loadingRoutes)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: CircularProgressIndicator(),
                    ),
                  if (_routeError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _routeError!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  if (_loadingAmenities)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Loading map datasets…',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  if (_routeOptions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _autoSelectedRoute
                                  ? 'Auto-selected Route ${_selectedRouteIndex + 1} (tap to change)'
                                  : 'Route ${_selectedRouteIndex + 1} selected',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _showRouteOptionsSheet,
                            child: const Text(
                              'Choose route',
                              style: TextStyle(color: Color(0xFF00FF00)),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (_tileErrorMessage != null && _tileErrorCount > 3)
            Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _tileErrorMessage!,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _tileErrorCount = 0;
                          _tileErrorMessage = null;
                        });
                      },
                      child: const Text(
                        'Retry map tiles',
                        style: TextStyle(color: Color(0xFF00FF00)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_isRideActive)
            Positioned(
              top: 50,
              left: 20,
              child: Column(
                children: [
                  FloatingActionButton.extended(
                    heroTag: 'test_mode_toggle',
                    onPressed: _toggleTestMode,
                    backgroundColor:
                        _testMode ? Colors.purple : Colors.grey.shade700,
                    label: Text(_testMode ? 'TEST ON' : 'TEST OFF'),
                    icon: const Icon(Icons.science),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    heroTag: 'nearest_fountain',
                    onPressed: _routeToNearestFountain,
                    backgroundColor: Colors.lightBlue,
                    label: const Text('FOUNTAIN'),
                    icon: const Icon(Icons.water_drop),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton.extended(
                    heroTag: 'report_issue',
                    onPressed: () => _reportPothole(isManual: true),
                    backgroundColor: Colors.orange,
                    label: const Text('REPORT'),
                    icon: const Icon(Icons.add_alert),
                  ),
                ],
              ),
            ),

          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              onPressed: _isRideActive ? _stopRide : _startRide,
              icon: Icon(_isRideActive ? Icons.stop : Icons.directions_bike),
              label: Text(_isRideActive ? 'STOP RIDE' : 'START RIDE'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRideActive
                    ? Colors.red
                    : const Color(0xFF00FF00),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.all(20),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 1,
        onTap: _onNavTap,
      ),
    );
  }
}
