import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../services/sensor_service.dart';
import '../services/navigation_service.dart';
import 'manual_report_dialog.dart';
import 'ride_summary_screen.dart';

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

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final SensorService _sensorService = SensorService();
  final NavigationService _navService = NavigationService();
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;
  StreamSubscription<Position>? _positionSub;
  LatLng _currentLocation = const LatLng(45.4642, 9.1900);
  LatLng? _startLocation;

  bool _isRideActive = false;
  bool _isLoadingLocation = true;

  List<Map<String, dynamic>> _searchResults = [];
  bool _showResults = false;

  List<LatLng> _routePoints = [];
  final List<LatLng> _ridePath = [];
  bool _hasRoute = false;

  final List<PotholeReport> _sessionReports = [];
  DateTime? _rideStartTime;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final Position position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLoadingLocation = false;
      });
      _mapController.move(_currentLocation, 15);
    }
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
    });

    final destLat = double.parse(place['lat']);
    final destLng = double.parse(place['lon']);
    final destPoint = LatLng(destLat, destLng);

    final route = await _navService.getBikeRoute(_currentLocation, destPoint);

    if (mounted) {
      setState(() {
        _routePoints = route;
        _hasRoute = true;
      });
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([_currentLocation, destPoint]),
          padding: const EdgeInsets.all(50),
        ),
      );
    }
  }

  void _startRide() {
    if (!_hasRoute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination first!')),
      );
      return;
    }

    setState(() {
      _isRideActive = true;
      _startLocation = _currentLocation;
      _sessionReports.clear();
      _rideStartTime = DateTime.now();
      _ridePath
        ..clear()
        ..add(_currentLocation);
    });

    _sensorService.startListening(() => _reportPothole(isManual: false));

    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream().listen((pos) {
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _currentLocation = loc;
        _ridePath.add(loc);
      });
    });
  }

  void _stopRide() {
    _sensorService.stopListening();
    _positionSub?.cancel();
    setState(() => _isRideActive = false);

    final rideDuration = DateTime.now().difference(_rideStartTime ?? DateTime.now());

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RideSummaryScreen(
            routePoints: _ridePath.isNotEmpty ? _ridePath : _routePoints,
            reports: _sessionReports,
            startPoint: _startLocation ?? _currentLocation,
            endPoint: _currentLocation,
            rideDuration: rideDuration,
          ),
        ),
      );
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

  @override
  void dispose() {
    _debounce?.cancel();
    _sensorService.stopListening();
    _positionSub?.cancel();
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
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
              if (_hasRoute)
                PolylineLayer(
                  polylines: [
                    Polyline(points: _routePoints, strokeWidth: 4.0, color: Colors.blue),
                  ],
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
                ],
              ),
            ],
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
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onTap: () => _selectDestination(place),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

          if (_isRideActive)
            Positioned(
              top: 50,
              right: 20,
              child: FloatingActionButton.extended(
                onPressed: () => _reportPothole(isManual: true),
                backgroundColor: Colors.orange,
                label: const Text('REPORT'),
                icon: const Icon(Icons.add_alert),
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
                backgroundColor: _isRideActive ? Colors.red : const Color(0xFF00FF00),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.all(20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
