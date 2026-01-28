import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_bottom_nav.dart';
import 'auth_screen.dart';
import 'dashboard_screen.dart';
import 'profile_screen.dart';
import 'recording_screen.dart';
import 'ride_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with WidgetsBindingObserver {
  late Future<List<RideHistoryEntry>> _ridesFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ridesFuture = _fetchRides();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshRides();
    }
  }

  void _refreshRides() {
    setState(() {
      _ridesFuture = _fetchRides();
    });
  }

  Future<List<RideHistoryEntry>> _fetchRides() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return [];

    try {
      // Try to fetch with end coordinates and distance_km
      final rows =
          await client
                  .from('rides')
                  .select(
                    'id,start_time,end_time,start_lat,start_lon,end_lat,end_lon,distance_km',
                  )
                  .eq('user_id', user.id)
                  .order('start_time', ascending: false)
              as List<dynamic>;

      debugPrint('[HISTORY] Fetched ${rows.length} rides with end coords');
      return rows.map((row) => RideHistoryEntry.fromJson(row)).toList();
    } catch (e) {
      debugPrint('[HISTORY] Full query failed: $e');
      try {
        // Fallback without distance_km
        final rows =
            await client
                    .from('rides')
                    .select(
                      'id,start_time,end_time,start_lat,start_lon,end_lat,end_lon',
                    )
                    .eq('user_id', user.id)
                    .order('start_time', ascending: false)
                as List<dynamic>;
        debugPrint(
          '[HISTORY] Fetched ${rows.length} rides without distance_km',
        );
        return rows.map((row) => RideHistoryEntry.fromJson(row)).toList();
      } catch (e2) {
        debugPrint('[HISTORY] Query without distance_km failed: $e2');
        try {
          // Minimal fallback
          final rows =
              await client
                      .from('rides')
                      .select('id,start_time,end_time,start_lat,start_lon')
                      .eq('user_id', user.id)
                      .order('start_time', ascending: false)
                  as List<dynamic>;
          debugPrint('[HISTORY] Fetched ${rows.length} rides (minimal)');
          return rows.map((row) => RideHistoryEntry.fromJson(row)).toList();
        } catch (_) {
          return [];
        }
      }
    }
  }

  void _onNavTap(int index) {
    if (index == 2) return;
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
      case 1:
        return const RecordingScreen();
      case 3:
        return const ProfileScreen();
      default:
        return null;
    }
  }

  Widget _buildGuestMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            const Text(
              'Sign in to view your ride history',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Record trips and track your cycling progress by creating an account.',
              style: TextStyle(color: Colors.grey, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.login),
              label: const Text('SIGN IN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FF00),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final isGuest = user == null;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Ride History'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!isGuest)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.grey),
              onPressed: _refreshRides,
            ),
        ],
      ),
      body: isGuest
          ? _buildGuestMessage()
          : FutureBuilder<List<RideHistoryEntry>>(
              future: _ridesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final rides = snapshot.data ?? [];
                if (rides.isEmpty) {
                  return const Center(
                    child: Text(
                      'No rides yet. Start a ride to see it here.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rides.length,
                  itemBuilder: (context, index) {
                    final ride = rides[index];
                    return _RideCard(
                      ride: ride,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RideDetailScreen(rideId: ride.id),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
      bottomNavigationBar: AppBottomNav(currentIndex: 2, onTap: _onNavTap),
    );
  }
}

class RideHistoryEntry {
  final String id;
  final DateTime? startTime;
  final DateTime? endTime;
  final LatLng? startPoint;
  final LatLng? endPoint;
  final double? storedDistanceKm; // Distance stored in database
  final bool? completed;
  final bool? reachedDestination;

  const RideHistoryEntry({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.startPoint,
    required this.endPoint,
    this.storedDistanceKm,
    required this.completed,
    required this.reachedDestination,
  });

  factory RideHistoryEntry.fromJson(Map<String, dynamic> json) {
    // Parse stored distance
    double? storedDist;
    if (json['distance_km'] != null) {
      storedDist = double.tryParse(json['distance_km'].toString());
    }

    return RideHistoryEntry(
      id: json['id']?.toString() ?? '-',
      startTime: _parseDate(json['start_time']),
      endTime: _parseDate(json['end_time']),
      startPoint: _parseLatLng(json['start_lat'], json['start_lon']),
      endPoint: _parseLatLng(json['end_lat'], json['end_lon']),
      storedDistanceKm: storedDist,
      completed: json['completed'] == true,
      reachedDestination: json['reached_destination'] == true,
    );
  }

  bool get isCompleted => completed == true || endTime != null;

  bool get isEndedEarly {
    if (endTime == null) return false;
    if (reachedDestination == null) return false;
    return reachedDestination == false;
  }

  bool get isStaleWithoutEnd {
    if (endTime != null) return false;
    if (startTime == null) return false;
    return DateTime.now().difference(startTime!).inMinutes >= 5;
  }

  Duration? get duration {
    if (startTime == null || endTime == null) return null;
    return endTime!.difference(startTime!);
  }

  /// Returns stored distance if available, otherwise calculates from coordinates
  double? get distanceKm {
    // Prefer stored distance from database (only if > 0.001 km = 1 meter)
    if (storedDistanceKm != null && storedDistanceKm! > 0.001) {
      return storedDistanceKm;
    }
    // Fallback: calculate straight-line distance from start to end
    if (startPoint == null || endPoint == null) return null;
    final calculated = const Distance().as(
      LengthUnit.Kilometer,
      startPoint!,
      endPoint!,
    );
    debugPrint(
      '[HISTORY] Calculated fallback distance: $calculated km from $startPoint to $endPoint',
    );
    return calculated;
  }

  /// Whether distance is actual tracked distance or just straight-line estimate
  bool get isActualDistance =>
      storedDistanceKm != null && storedDistanceKm! > 0.001;

  double? get avgSpeedKmh {
    final duration = this.duration;
    final distance = distanceKm;
    if (duration == null || distance == null) return null;
    final hours = duration.inSeconds / 3600;
    if (hours <= 0) return null;
    return distance / hours;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static LatLng? _parseLatLng(dynamic lat, dynamic lon) {
    if (lat == null || lon == null) return null;
    final latVal = double.tryParse(lat.toString());
    final lonVal = double.tryParse(lon.toString());
    if (latVal == null || lonVal == null) return null;
    return LatLng(latVal, lonVal);
  }
}

class _RideCard extends StatelessWidget {
  final RideHistoryEntry ride;
  final VoidCallback onTap;

  const _RideCard({required this.ride, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final duration = ride.duration;
    final distance = ride.distanceKm;
    final speed = ride.avgSpeedKmh;
    final startLabel = ride.startTime != null
        ? _formatDateTime(ride.startTime!)
        : 'Unknown start';

    // Determine status label and color
    final String statusLabel;
    final Color statusColor;
    if (ride.endTime != null) {
      statusLabel = 'Completed';
      statusColor = const Color(0xFF00FF00);
    } else if (ride.isStaleWithoutEnd) {
      statusLabel = 'Ended';
      statusColor = Colors.orange;
    } else {
      statusLabel = 'In progress';
      statusColor = Colors.grey;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_bike, color: Color(0xFF00FF00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    startLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: const TextStyle(color: Colors.black, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'Ride ID', value: ride.id),
            if (ride.startPoint != null)
              _InfoRow(label: 'Start', value: _formatLatLng(ride.startPoint!)),
            if (ride.endPoint != null)
              _InfoRow(label: 'End', value: _formatLatLng(ride.endPoint!)),
            if (duration != null)
              _InfoRow(label: 'Duration', value: _formatDuration(duration)),
            if (distance != null)
              _InfoRow(
                label: 'Distance',
                value:
                    '${distance.toStringAsFixed(2)} km${ride.isActualDistance ? '' : ' (estimated)'}',
              ),
            if (speed != null)
              _InfoRow(
                label: 'Avg speed',
                value: '${speed.toStringAsFixed(1)} km/h',
              ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final date =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date  $time';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String _formatLatLng(LatLng point) {
    return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
