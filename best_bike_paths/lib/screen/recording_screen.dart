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
import '../services/weather_service.dart';
import '../services/segment_coloring_service.dart';
import '../services/local_cache_service.dart';
import '../services/background_ride_service.dart';
import '../services/ml_pothole_service.dart';
import 'manual_report_dialog.dart';
import 'ride_summary_screen.dart';
import 'verification_dialog.dart';
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
  final String?
  trustLevel; // verified_strong, verified, likely, reported, unverified
  final int? daysUntilExpiry;
  final int upvotes;
  final int downvotes;

  const AnomalyPoint({
    required this.location,
    required this.weight,
    this.trustLevel,
    this.daysUntilExpiry,
    this.upvotes = 0,
    this.downvotes = 0,
  });

  /// Get opacity based on trust level
  double get opacity {
    switch (trustLevel) {
      case 'verified_strong':
        return 1.0;
      case 'verified':
        return 0.95;
      case 'likely':
        return 0.85;
      case 'reported':
        return 0.7;
      case 'unverified':
        return 0.5;
      default:
        return 0.8;
    }
  }

  /// Get marker size multiplier based on trust level
  double get sizeMultiplier {
    switch (trustLevel) {
      case 'verified_strong':
        return 1.2;
      case 'verified':
        return 1.1;
      case 'likely':
        return 1.0;
      case 'reported':
        return 0.9;
      case 'unverified':
        return 0.8;
      default:
        return 1.0;
    }
  }
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
  final String? resumeRideId;
  final bool guestMode;

  const RecordingScreen({super.key, this.resumeRideId, this.guestMode = false});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with WidgetsBindingObserver {
  final SensorService _sensorService = SensorService();
  final MLPotholeDetectionService _mlPotholeService = MLPotholeDetectionService();
  final NavigationService _navService = NavigationService();
  final WeatherService _weatherService = WeatherService();
  final LocalCacheService _cacheService = LocalCacheService.instance;
  final BackgroundRideService _backgroundService = BackgroundRideService();
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<SyncStatus>? _syncStatusSub;
  StreamSubscription<int>? _pendingCountSub;
  LatLng _currentLocation = const LatLng(45.4642, 9.1900);
  LatLng? _startLocation;
  LatLng? _destinationPoint;
  double _currentSpeedMps = 0;

  bool _isRideActive = false;
  bool _isOffline = false;
  int _pendingReportCount = 0;
  SyncStatus _syncStatus = SyncStatus.idle;

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

  // Weather alerts
  WeatherData? _weatherData;
  bool _showWeatherAlerts = false;

  // Segment coloring
  List<RoadSegment> _coloredSegments = [];
  bool _showColoredSegments = true;
  List<AnomalyData> _anomalyDataList = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeOfflineSupport();
    _initializeLocation();
    _loadPreferencesAndData();
    // Note: _fetchWeather() is now called inside _initializeLocation after GPS is ready
    // If resuming a specific ride from dashboard, handle that
    if (widget.resumeRideId != null) {
      _resumeSpecificRide(widget.resumeRideId!);
    } else {
      _restoreRideIfNeeded();
    }
  }

  /// Resume a specific unfinished ride (called from dashboard)
  Future<void> _resumeSpecificRide(String rideId) async {
    try {
      final ride = await Supabase.instance.client
          .from('rides')
          .select('id,start_time,start_lat,start_lon')
          .eq('id', rideId)
          .maybeSingle();

      if (ride == null) {
        debugPrint('[RIDE] Could not find ride $rideId');
        return;
      }

      final startLat = (ride['start_lat'] as num?)?.toDouble() ?? 0;
      final startLon = (ride['start_lon'] as num?)?.toDouble() ?? 0;
      final startTimeRaw = ride['start_time']?.toString();

      _restoringRide = true;
      _startLocation = LatLng(startLat, startLon);
      _activeRideId = rideId;
      _rideStartTime = startTimeRaw != null
          ? DateTime.tryParse(startTimeRaw)
          : null;

      setState(() {
        _isRideActive = true;
        _pendingAutoEndDialog = false;
        _autoEndDismissed = false;
      });
      await _persistRideState();
      await _resumeActiveRide();
    } catch (e) {
      debugPrint('[RIDE] Error resuming ride $rideId: $e');
    }
  }

  void _startLocationStream() {
    _positionSub?.cancel();
    final settings = _buildLocationSettings();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(_onPositionUpdate);
    debugPrint('[GPS] Location stream started');
  }

  /// Locate me button - zoom to current location
  Future<void> _locateMe() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final loc = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentLocation = loc;
      });
      _mapController.move(loc, 16);
      debugPrint('[GPS] Located user at $loc');
    } catch (e) {
      debugPrint('[GPS] Error locating user: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get current location')),
        );
      }
    }
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
    _mlPotholeService.updateSpeed(_currentSpeedMps);
    _mlPotholeService.setLocation(loc.latitude, loc.longitude);
    if (_isRideActive) {
      _checkDestinationArrival(loc);
      // Update background notification with current stats
      _updateBackgroundNotification();
    }
  }
  
  /// Update the background service notification with current ride stats
  void _updateBackgroundNotification() {
    if (!_backgroundService.isRunning || _rideStartTime == null) return;
    
    final duration = DateTime.now().difference(_rideStartTime!);
    final distanceKm = _computeRideDistanceKm(_ridePath);
    final speedKmh = _currentSpeedMps * 3.6; // m/s to km/h
    
    _backgroundService.updateNotification(
      distanceKm: distanceKm,
      duration: duration,
      speedKmh: speedKmh,
    );
  }

  void _checkDestinationArrival(LatLng location) {
    final destination = _destinationPoint;
    if (destination == null) return;
    final meters = const Distance().as(LengthUnit.Meter, destination, location);
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

    // Parse the start time - ensure it's in local time
    if (startTimeRaw != null && startTimeRaw.isNotEmpty) {
      final parsed = DateTime.tryParse(startTimeRaw);
      _rideStartTime = parsed?.toLocal();
    } else {
      _rideStartTime = null;
    }

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
    _mlPotholeService.updateSpeed(_currentSpeedMps);
    _mlPotholeService.setLocation(_currentLocation.latitude, _currentLocation.longitude);

    _sensorService.startListening(
      () => _reportPothole(isManual: false),
      onDebug: (data) {
        if (!mounted) return;
        setState(() => _debugStats = data);
      },
    );
    
    // Start ML-powered pothole detection (runs in parallel with existing detection)
    _mlPotholeService.startListening(
      onDetected: (lat, lon, severity) {
        debugPrint('[ML] Pothole detected at ($lat, $lon) with severity: $severity');
        _reportPothole(isManual: false, mlSeverity: severity);
      },
      onDebugCallback: (data) {
        debugPrint('[ML_DEBUG] ${data.toString()}');
      },
    );
    
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

  // ========== OFFLINE SUPPORT ==========

  void _initializeOfflineSupport() {
    // Listen to sync status changes
    _syncStatusSub = _cacheService.syncStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _syncStatus = status;
          _isOffline = status == SyncStatus.offline;
        });
        
        // Show snackbar for sync events
        if (status == SyncStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Offline reports synced successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });

    // Listen to pending report count
    _pendingCountSub = _cacheService.pendingCountStream.listen((count) {
      if (mounted) {
        setState(() => _pendingReportCount = count);
      }
    });

    // Set initial state
    _isOffline = !_cacheService.isOnline;
  }

  /// Save report to local cache when offline
  Future<void> _saveReportOffline(LatLng location, String category, bool isManual) async {
    await _cacheService.savePendingReport(
      location: location,
      category: category,
      isManual: isManual,
      rideId: _activeRideId,
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$category saved offline. Will sync when online.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Build offline indicator widget
  Widget _buildOfflineIndicator() {
    if (!_isOffline && _pendingReportCount == 0) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _isOffline ? Colors.orange.shade800 : Colors.blue.shade700,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isOffline ? Icons.cloud_off : Icons.cloud_upload,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              _isOffline 
                  ? 'Offline' 
                  : '$_pendingReportCount pending',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_syncStatus == SyncStatus.syncing) ...[
              const SizedBox(width: 6),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
      // Start continuous location stream (GPS always on)
      _startLocationStream();
      // Fetch weather after we have real GPS coordinates
      debugPrint(
        '[WEATHER] Fetching weather for ${position.latitude}, ${position.longitude}',
      );
      _fetchWeather();
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

  /// Handle long-press on map to select destination
  Future<void> _onMapLongPress(TapPosition tapPosition, LatLng point) async {
    // First, get the address for the selected point (reverse geocoding)
    String locationName = 'Selected Location';
    try {
      final response = await _navService.reverseGeocode(point.latitude, point.longitude);
      if (response != null && response.isNotEmpty) {
        locationName = response.split(',')[0];
      }
    } catch (e) {
      debugPrint('[MAP] Reverse geocoding failed: $e');
    }

    // Show confirmation dialog
    if (!mounted) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.location_on, color: Color(0xFF00FF00)),
            SizedBox(width: 8),
            Text(
              'Set Destination?',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Do you want to set this location as your destination?',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.place, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      locationName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF00),
              foregroundColor: Colors.black,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    // If user cancelled, don't proceed
    if (confirmed != true) return;

    // User confirmed, proceed with setting destination
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Setting destination...'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    setState(() {
      _showResults = false;
      _loadingRoutes = true;
      _routeError = null;
    });

    _searchController.text = locationName;
    FocusScope.of(context).unfocus();

    _destinationPoint = point;
    if (_isRideActive) {
      await _persistRideState();
    }

    final options = await _navService.getBikeRoutes(
      _currentLocation,
      point,
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

      // Compute colored segments for the selected route
      if (_routePoints.isNotEmpty) {
        _computeColoredSegments();
      }

      if (_routeOptions.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([_currentLocation, point]),
            padding: const EdgeInsets.all(50),
          ),
        );
        _showRouteOptionsSheet();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Destination set! Auto-selected Route ${bestIndex + 1}.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
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

      // Compute colored segments for the selected route
      if (_routePoints.isNotEmpty) {
        _computeColoredSegments();
      }

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
      final cobblePenalty = _avoidCobblestones
          ? option.cobblestoneScore * 2
          : 0;
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
    final surfacePoints = _avoidCobblestones
        ? _surfacePoints
        : <SurfacePoint>[];

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
            final meters = distance.as(
              LengthUnit.Meter,
              surface.location,
              point,
            );
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

  /// Fetch anomaly points from the database
  /// Uses active_anomalies view which filters out expired/removed anomalies
  Future<List<AnomalyPoint>> _fetchAnomalyPoints() async {
    try {
      // Use active_anomalies view for proper lifecycle filtering
      final rows =
          await Supabase.instance.client
                  .from('active_anomalies')
                  .select(
                    'id,location,severity,category,verified,upvotes,downvotes,trust_level,days_until_expiry',
                  )
                  .order('created_at', ascending: false)
                  .limit(500)
              as List<dynamic>;

      // Store full data for verification dialog
      _fetchedAnomaliesRaw = rows.cast<Map<String, dynamic>>();

      return rows
          .map((row) => _parseAnomalyPoint(row))
          .whereType<AnomalyPoint>()
          .toList();
    } catch (e) {
      debugPrint('Failed to fetch anomalies: $e');
      // Fallback to anomalies table if view doesn't exist yet
      try {
        final rows =
            await Supabase.instance.client
                    .from('anomalies')
                    .select(
                      'id,location,severity,category,verified,upvotes,downvotes',
                    )
                    .filter('expires_at', 'is', null) // Only non-expired
                    .order('created_at', ascending: false)
                    .limit(500)
                as List<dynamic>;
        _fetchedAnomaliesRaw = rows.cast<Map<String, dynamic>>();
        return rows
            .map((row) => _parseAnomalyPoint(row))
            .whereType<AnomalyPoint>()
            .toList();
      } catch (e2) {
        debugPrint('Fallback also failed: $e2');
        return [];
      }
    }
  }

  // Store raw anomaly data for verification
  List<Map<String, dynamic>> _fetchedAnomaliesRaw = [];

  IconData _getAnomalyIcon(String category) {
    switch (category.toLowerCase()) {
      case 'pothole':
        return Icons.warning;
      case 'bump':
        return Icons.trending_up;
      case 'crack':
        return Icons.grain;
      case 'debris':
      case 'broken glass':
        return Icons.broken_image;
      case 'construction':
        return Icons.construction;
      case 'flooding':
        return Icons.water;
      default:
        return Icons.report_problem;
    }
  }

  AnomalyPoint? _parseAnomalyPoint(Map<String, dynamic> row) {
    final location = _parseGeoPoint(row['location']);
    if (location == null) return null;
    final severity = row['severity']?.toString();
    return AnomalyPoint(
      location: location,
      weight: _severityWeight(severity),
      trustLevel: row['trust_level']?.toString(),
      daysUntilExpiry: row['days_until_expiry'] as int?,
      upvotes: (row['upvotes'] as num?)?.toInt() ?? 0,
      downvotes: (row['downvotes'] as num?)?.toInt() ?? 0,
    );
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
      final match = RegExp(
        r'POINT\(([-\d\.]+)\s+([-\d\.]+)\)',
      ).firstMatch(location);
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
      final rows =
          await Supabase.instance.client
                  .from('fountains')
                  .select('osm_id,location')
                  .limit(1200)
              as List<dynamic>;

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
    double nearestMeters = distance.as(
      LengthUnit.Meter,
      current,
      fountains.first.location,
    );
    for (final fountain in fountains.skip(1)) {
      final meters = distance.as(LengthUnit.Meter, current, fountain.location);
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearest = fountain;
      }
    }

    _destinationPoint = nearest.location;
    _searchController.text = 'Nearest fountain';

    final options = await _navService.getBikeRoutes(current, nearest.location);

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
          const SnackBar(content: Text('Routing to the nearest fountain.')),
        );
      }
    }
  }

  Future<SurfaceData> _fetchSurfaceSegments() async {
    try {
      final rows =
          await Supabase.instance.client
                  .from('surface_segments')
                  .select('surface,centroid,geometry')
                  .limit(1500)
              as List<dynamic>;

      final points = <SurfacePoint>[];
      final segments = <List<LatLng>>[];

      for (final row in rows) {
        final surface = row['surface']?.toString();
        final centroid = _parseGeoPoint(row['centroid']);
        if (centroid != null) {
          points.add(
            SurfacePoint(location: centroid, weight: _surfaceWeight(surface)),
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
            .map(
              (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
            )
            .toList();
      }
      if (type == 'Polygon' && coords is List && coords.isNotEmpty) {
        final ring = coords.first as List;
        return ring
            .map(
              (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
            )
            .toList();
      }
      if (type == 'MultiLineString' && coords is List && coords.isNotEmpty) {
        final first = coords.first as List;
        return first
            .map(
              (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
            )
            .toList();
      }
    }
    return [];
  }

  List<LatLng> _sampleRoutePoints(List<LatLng> points, {int maxPoints = 200}) {
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

    _startLocationStream();
    
    // Start background service to keep tracking when screen is off
    await _backgroundService.startBackgroundTracking();
    debugPrint('[RIDE] Background tracking started');
  }

  Future<void> _stopRide() async {
    _sensorService.stopListening();
    _mlPotholeService.stopListening();
    _positionSub?.cancel();

    // Save all data before clearing state
    final rideId = _activeRideId;
    final ridePath = List<LatLng>.from(_ridePath); // Copy path before clearing
    final startLocation = _startLocation ?? _currentLocation; // Copy start location
    final endLocation = _currentLocation; // Copy end location
    final rideStartTime = _rideStartTime; // Copy start time
    
    debugPrint('[RIDE] Stopping ride: ${ridePath.length} points, start: $startLocation, end: $endLocation');

    setState(() {
      _isRideActive = false;
      _activeRideId = null; // Clear to prevent duplicate operations
    });
    await _clearRideState();

    // Calculate ride duration - ensure it's positive
    Duration rideDuration;
    if (rideStartTime != null) {
      rideDuration = DateTime.now().difference(rideStartTime);
      // If negative (clock skew), use absolute value
      if (rideDuration.isNegative) {
        rideDuration = rideDuration.abs();
      }
    } else {
      rideDuration = Duration.zero;
    }

    // Calculate distance from recorded path
    final distanceKm = _computeRideDistanceKm(ridePath);
    debugPrint('[RIDE] Calculated distance: ${distanceKm.toStringAsFixed(2)} km from ${ridePath.length} points');

    if (rideId != null) {
      try {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        
        // Update ride with end time and distance
        await Supabase.instance.client
            .from('rides')
            .update({
              'end_time': DateTime.now().toIso8601String(),
              'distance_km': distanceKm,
              'end_lat': _currentLocation.latitude,
              'end_lon': _currentLocation.longitude,
            })
            .eq('id', rideId);
        debugPrint('[RIDE] Stopped ride: $rideId with distance: $distanceKm km');
        
        // Update user's total distance in profiles table
        if (userId != null && distanceKm > 0) {
          await _updateUserTotalDistance(userId, distanceKm);
        }
      } catch (e) {
        debugPrint('[RIDE] Failed to update ride on stop: $e');
        // Try updating without end_lat/end_lon if columns don't exist
        try {
          await Supabase.instance.client
              .from('rides')
              .update({
                'end_time': DateTime.now().toIso8601String(),
                'distance_km': distanceKm,
              })
              .eq('id', rideId);
          debugPrint('[RIDE] Updated ride without location columns');
          
          final userId = Supabase.instance.client.auth.currentUser?.id;
          if (userId != null && distanceKm > 0) {
            await _updateUserTotalDistance(userId, distanceKm);
          }
        } catch (e2) {
          debugPrint('[RIDE] Fallback update also failed: $e2');
        }
      }
    }

    // Stop background service
    await _backgroundService.stopBackgroundTracking();
    debugPrint('[RIDE] Background tracking stopped');

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RideSummaryScreen(
            routePoints: ridePath.isNotEmpty ? ridePath : _routePoints,
            reports: _sessionReports,
            startPoint: startLocation,
            endPoint: endLocation,
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
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => target));
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

  Future<void> _reportPothole({required bool isManual, double? mlSeverity}) async {
    String category = 'Bump';

    if (isManual) {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => const ManualReportDialog(),
      );
      if (result == null) return;
      category = result;
    } else if (mlSeverity != null && mlSeverity > 0.7) {
      // ML detected severe pothole
      category = 'Pothole (ML Detected)';
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

    // If offline, save to local cache for later sync
    if (_isOffline) {
      await _saveReportOffline(potholeLoc, category, isManual);
    } else {
      if (mounted) {
        final severityText = mlSeverity != null 
            ? ' (Severity: ${(mlSeverity * 100).toInt()}%)' 
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$category Recorded!$severityText Added to Summary.'),
            backgroundColor: isManual ? Colors.orange : (mlSeverity != null && mlSeverity > 0.5 ? Colors.deepOrange : Colors.red),
            duration: const Duration(milliseconds: 500),
          ),
        );
      }
    }
  }

  /// Calculate total distance in km from a list of GPS points
  double _computeRideDistanceKm(List<LatLng> points) {
    if (points.length < 2) return 0;
    const dist = Distance();
    double km = 0;
    for (int i = 0; i < points.length - 1; i++) {
      km += dist.as(LengthUnit.Kilometer, points[i], points[i + 1]);
    }
    return km;
  }

  /// Update user's total distance in profiles table
  Future<void> _updateUserTotalDistance(String userId, double addedDistanceKm) async {
    try {
      // First, get current total distance
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('total_distance_km')
          .eq('id', userId)
          .maybeSingle();

      final currentDistance = (profile?['total_distance_km'] as num?)?.toDouble() ?? 0.0;
      final newTotalDistance = currentDistance + addedDistanceKm;

      // Update the profile with new total
      await Supabase.instance.client
          .from('profiles')
          .upsert({
            'id': userId,
            'total_distance_km': newTotalDistance,
          });

      debugPrint('[RIDE] Updated user total distance: $currentDistance + $addedDistanceKm = $newTotalDistance km');
    } catch (e) {
      debugPrint('[RIDE] Failed to update user total distance: $e');
      
      // Try user_stats table as fallback
      try {
        final stats = await Supabase.instance.client
            .from('user_stats')
            .select('total_distance_km')
            .eq('user_id', userId)
            .maybeSingle();

        final currentDistance = (stats?['total_distance_km'] as num?)?.toDouble() ?? 0.0;
        final newTotalDistance = currentDistance + addedDistanceKm;

        await Supabase.instance.client
            .from('user_stats')
            .upsert({
              'user_id': userId,
              'total_distance_km': newTotalDistance,
            });

        debugPrint('[RIDE] Updated user_stats total distance: $newTotalDistance km');
      } catch (e2) {
        debugPrint('[RIDE] Fallback user_stats update also failed: $e2');
      }
    }
  }

  // ========== WEATHER ALERTS ==========

  Future<void> _fetchWeather() async {
    debugPrint('[WEATHER] Starting weather fetch...');
    final weather = await _weatherService.getWeather(
      _currentLocation.latitude,
      _currentLocation.longitude,
    );
    debugPrint(
      '[WEATHER] Weather result: ${weather?.temperature}°C, ${weather?.condition}',
    );
    if (mounted && weather != null) {
      setState(() {
        _weatherData = weather;
        debugPrint(
          '[WEATHER] Weather data set: ${_weatherData?.temperature}°C',
        );
        // Show weather alert banner if there are warnings or dangers
        _showWeatherAlerts = weather.alerts.any(
          (a) =>
              a.severity == AlertSeverity.warning ||
              a.severity == AlertSeverity.danger,
        );
      });
    } else {
      debugPrint('[WEATHER] Weather fetch failed or widget not mounted');
    }
  }

  Widget _buildWeatherBanner() {
    if (_weatherData == null || !_showWeatherAlerts)
      return const SizedBox.shrink();

    final alerts = _weatherData!.alerts
        .where(
          (a) =>
              a.severity == AlertSeverity.warning ||
              a.severity == AlertSeverity.danger,
        )
        .toList();

    if (alerts.isEmpty) return const SizedBox.shrink();

    final alert = alerts.first;
    final isDanger = alert.severity == AlertSeverity.danger;

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDanger
            ? Colors.red.withOpacity(0.9)
            : Colors.orange.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(alert.icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  alert.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  alert.message,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            onPressed: () => setState(() => _showWeatherAlerts = false),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  /// Build a compact weather info chip that's always visible
  Widget _buildWeatherInfoChip() {
    debugPrint(
      '[WEATHER] Building weather chip, _weatherData is ${_weatherData != null ? "available" : "null"}',
    );
    if (_weatherData == null) return const SizedBox.shrink();

    final weather = _weatherData!;
    final icon = _getWeatherConditionIcon(weather.condition);
    final isSafe = weather.isSafeForCycling;
    debugPrint(
      '[WEATHER] Chip: ${weather.temperature}°C, icon: $icon, safe: $isSafe',
    );

    return GestureDetector(
      onTap: () {
        // Show detailed weather info
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                const Text(
                  'Weather Conditions',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  weather.description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildWeatherDetailRow(
                  '🌡️',
                  'Temperature',
                  '${weather.temperature.toStringAsFixed(1)}°C',
                ),
                _buildWeatherDetailRow(
                  '💨',
                  'Wind',
                  '${weather.windSpeed.toStringAsFixed(1)} m/s',
                ),
                _buildWeatherDetailRow(
                  '💧',
                  'Humidity',
                  '${weather.humidity.toStringAsFixed(0)}%',
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSafe
                        ? Colors.green.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSafe ? Colors.green : Colors.red,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSafe ? Icons.check_circle : Icons.warning,
                        color: isSafe ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          weather.cyclingAdvice,
                          style: TextStyle(
                            color: isSafe
                                ? Colors.green.shade300
                                : Colors.red.shade300,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'OK',
                  style: TextStyle(color: Color(0xFF00FF00)),
                ),
              ),
            ],
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSafe
              ? Colors.green.withOpacity(0.85)
              : Colors.orange.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 4),
            Text(
              '${weather.temperature.toStringAsFixed(0)}°C',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherDetailRow(String icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _getWeatherConditionIcon(WeatherCondition condition) {
    switch (condition) {
      case WeatherCondition.clear:
        return '☀️';
      case WeatherCondition.cloudy:
        return '☁️';
      case WeatherCondition.rain:
        return '🌧️';
      case WeatherCondition.heavyRain:
        return '⛈️';
      case WeatherCondition.snow:
        return '❄️';
      case WeatherCondition.fog:
        return '🌫️';
      case WeatherCondition.wind:
        return '💨';
      case WeatherCondition.storm:
        return '🌩️';
    }
  }

  // ========== SEGMENT COLORING ==========

  Future<void> _computeColoredSegments() async {
    if (_routePoints.isEmpty) return;

    // Fetch anomalies for coloring if not already loaded
    if (_anomalyDataList.isEmpty) {
      await _fetchAnomaliesForColoring();
    }

    final segments = SegmentColoringService.computeColoredSegments(
      _routePoints,
      _anomalyDataList,
    );

    if (mounted) {
      setState(() {
        _coloredSegments = segments;
      });
    }
  }

  Future<void> _fetchAnomaliesForColoring() async {
    try {
      final result = await Supabase.instance.client
          .from('anomalies')
          .select('id, location, severity, category, verified')
          .limit(1000);

      _anomalyDataList = (result as List)
          .map((json) => AnomalyData.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching anomalies for coloring: $e');
    }
  }

  List<Polyline> _buildColoredPolylines() {
    if (!_showColoredSegments || _coloredSegments.isEmpty) {
      return [];
    }

    return _coloredSegments.map((segment) {
      return Polyline(
        points: segment.points,
        strokeWidth: 6.0,
        color: segment.color.withOpacity(0.8),
      );
    }).toList();
  }

  // ========== ANOMALY VERIFICATION ==========

  void _showVerificationDialog(Map<String, dynamic> anomaly) {
    if (widget.guestMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to verify hazard reports'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Parse location
    double? lat, lon;
    if (anomaly['location'] is String) {
      final locStr = anomaly['location'] as String;
      final match = RegExp(
        r'POINT\(([-\d.]+)\s+([-\d.]+)\)',
      ).firstMatch(locStr);
      if (match != null) {
        lon = double.tryParse(match.group(1)!);
        lat = double.tryParse(match.group(2)!);
      }
    }

    showDialog(
      context: context,
      builder: (context) => VerificationDialog(
        anomalyId: anomaly['id']?.toString() ?? '',
        category: anomaly['category']?.toString() ?? 'Unknown',
        latitude: lat,
        longitude: lon,
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sensorService.stopListening();
    _mlPotholeService.stopListening();
    _positionSub?.cancel();
    _syncStatusSub?.cancel();
    _pendingCountSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isRideActive,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // Show confirmation dialog when trying to leave during active ride
        await _showExitConfirmationDialog();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation,
                initialZoom: 15.0,
                onLongPress: _onMapLongPress,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                        // Green for selected route (remaining path to cover)
                        color: selected
                            ? const Color(0xFF00FF00)
                            : Colors.blueGrey.withOpacity(0.6),
                      );
                    }).toList(),
                  ),
                // Show covered path (ride path) in YELLOW
                if (_ridePath.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _ridePath,
                        strokeWidth: 6.0,
                        color: Colors.amber, // Yellow for covered path
                      ),
                    ],
                  ),
                // Colored segments overlay (safety score visualization)
                if (_showColoredSegments && _coloredSegments.isNotEmpty)
                  PolylineLayer(polylines: _buildColoredPolylines()),
                MarkerLayer(
                  markers: [
                    // Current location marker (blue navigation arrow)
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
                    // START marker (green flag)
                    if (_startLocation != null)
                      Marker(
                        point: _startLocation!,
                        width: 50,
                        height: 50,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'START',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.location_on,
                              color: Colors.green,
                              size: 30,
                            ),
                          ],
                        ),
                      ),
                    // DESTINATION marker (red flag)
                    if (_destinationPoint != null)
                      Marker(
                        point: _destinationPoint!,
                        width: 50,
                        height: 60,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'DESTINATION',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Icon(Icons.flag, color: Colors.red, size: 30),
                          ],
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
                    // Tappable anomaly markers for verification
                    // Markers are sized and styled based on trust level
                    ..._fetchedAnomaliesRaw.map((anomaly) {
                      final loc = _parseGeoPoint(anomaly['location']);
                      if (loc == null)
                        return const Marker(
                          point: LatLng(0, 0),
                          child: SizedBox.shrink(),
                        );
                      final category =
                          anomaly['category']?.toString() ?? 'Unknown';
                      final verified = anomaly['verified'] == true;
                      final trustLevel =
                          anomaly['trust_level']?.toString() ?? 'unverified';
                      final upvotes =
                          (anomaly['upvotes'] as num?)?.toInt() ?? 0;
                      final downvotes =
                          (anomaly['downvotes'] as num?)?.toInt() ?? 0;

                      // Calculate opacity and size based on trust level
                      double opacity;
                      double size;
                      switch (trustLevel) {
                        case 'verified_strong':
                          opacity = 1.0;
                          size = 38;
                          break;
                        case 'verified':
                          opacity = 0.95;
                          size = 34;
                          break;
                        case 'likely':
                          opacity = 0.85;
                          size = 32;
                          break;
                        case 'reported':
                          opacity = 0.7;
                          size = 28;
                          break;
                        case 'unverified':
                        default:
                          opacity = 0.5;
                          size = 24;
                          break;
                      }

                      // Reduce opacity further if heavily downvoted
                      if (downvotes > upvotes && downvotes >= 3) {
                        opacity = opacity * 0.6;
                      }

                      return Marker(
                        point: loc,
                        width: size,
                        height: size,
                        child: GestureDetector(
                          onTap: () => _showVerificationDialog(anomaly),
                          child: Opacity(
                            opacity: opacity,
                            child: Container(
                              decoration: BoxDecoration(
                                color: verified
                                    ? Colors.green.withOpacity(0.9)
                                    : trustLevel == 'likely'
                                    ? Colors.orange.withOpacity(0.9)
                                    : Colors.red.withOpacity(0.9),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: trustLevel == 'verified_strong'
                                      ? 3
                                      : 2,
                                ),
                                boxShadow: verified
                                    ? [
                                        BoxShadow(
                                          color: Colors.green.withOpacity(0.5),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Icon(
                                _getAnomalyIcon(category),
                                color: Colors.white,
                                size: size * 0.5,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),

            if (_debugStats.isNotEmpty)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DefaultTextStyle(
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Z g: ${_debugStats['zForceG']?.toStringAsFixed(2) ?? '-'}',
                        ),
                        Text(
                          'Raw Z: ${_debugStats['rawZ']?.toStringAsFixed(2) ?? '-'}',
                        ),
                        Text(
                          'Jerk: ${_debugStats['jerk']?.toStringAsFixed(2) ?? '-'} g/s',
                        ),
                        Text(
                          'Speed: ${_debugStats['speedKmh']?.toStringAsFixed(1) ?? '-'} km/h',
                        ),
                        Text(
                          'Thresh: ${_debugStats['threshold']?.toStringAsFixed(2) ?? '-'}',
                        ),
                        Text(
                          'Conf: ${_debugStats['confidence']?.toStringAsFixed(2) ?? '-'}',
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Offline indicator
            _buildOfflineIndicator(),

            if (!_isRideActive)
              Positioned(
                top: 50,
                left: 20,
                right: 20,
                child: Column(
                  children: [
                    // Weather alert banner
                    _buildWeatherBanner(),
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
                        child: ElevatedButton.icon(
                          onPressed: _loadingRoutes
                              ? null
                              : _routeToNearestFountain,
                          icon: const Icon(Icons.water_drop),
                          label: const Text('NEAREST FOUNTAIN'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.lightBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
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

            if (_isRideActive && !widget.guestMode)
              Positioned(
                top: 50,
                left: 20,
                child: Column(
                  children: [
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

            // START/STOP RIDE button - only for authenticated users
            if (!widget.guestMode)
              Positioned(
                bottom: 30,
                left: 20,
                right: 20,
                child: ElevatedButton.icon(
                  onPressed: _isRideActive ? _stopRide : _startRide,
                  icon: Icon(
                    _isRideActive ? Icons.stop : Icons.directions_bike,
                  ),
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

            // LOCATE ME button - helps user find their location
            Positioned(
              bottom: widget.guestMode ? 150 : 100,
              right: 16,
              child: FloatingActionButton(
                heroTag: 'locate_me',
                mini: true,
                backgroundColor: Colors.white,
                onPressed: _locateMe,
                child: const Icon(Icons.my_location, color: Colors.blue),
              ),
            ),

            // Color legend for segment coloring
            if (_showColoredSegments && _coloredSegments.isNotEmpty)
              Positioned(
                bottom: widget.guestMode ? 100 : 100,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Road Safety',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildLegendItem(Colors.green, 'Safe'),
                      _buildLegendItem(Colors.yellow, 'Caution'),
                      _buildLegendItem(Colors.red, 'Hazardous'),
                    ],
                  ),
                ),
              ),

            // Weather info chip (always visible when weather data available)
            if (_weatherData != null)
              Positioned(top: 16, right: 60, child: _buildWeatherInfoChip()),

            // Guest mode info banner
            if (widget.guestMode)
              Positioned(
                bottom: 30,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.white),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Guest Mode: View map and routes. Sign in to record rides and report issues.',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: AppBottomNav(currentIndex: 1, onTap: _onNavTap),
      ), // End of Scaffold (child of PopScope)
    ); // End of PopScope
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 9)),
      ],
    );
  }

  /// Show confirmation dialog when user tries to leave during active ride
  Future<void> _showExitConfirmationDialog() async {
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Ride in Progress'),
        content: const Text(
          'You have an active ride. What would you like to do?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('stay'),
            child: const Text('Continue Riding'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('end'),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('End Ride'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('leave'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave (ride stays in progress)'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    switch (result) {
      case 'end':
        await _stopRide();
        break;
      case 'leave':
        // Just navigate away - ride stays in progress in DB
        // but we should clear local state so SharedPreferences doesn't restore it
        // Actually, keep it so user can resume from dashboard
        Navigator.of(context).pop();
        break;
      case 'stay':
      default:
        // User chose to continue, do nothing
        break;
    }
  }
}
