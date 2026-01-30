import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'recording_screen.dart'; // This is your Map screen (renamed)
import 'auth_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import 'app_bottom_nav.dart';
import '../services/local_cache_service.dart';

/// Represents an unfinished ride that needs to be resolved
class UnfinishedRide {
  final String id;
  final DateTime startTime;
  final double? startLat;
  final double? startLon;

  const UnfinishedRide({
    required this.id,
    required this.startTime,
    this.startLat,
    this.startLon,
  });

  factory UnfinishedRide.fromJson(Map<String, dynamic> json) {
    // Parse the timestamp and convert to local time
    final rawTime = json['start_time']?.toString() ?? '';
    DateTime parsedTime = DateTime.tryParse(rawTime) ?? DateTime.now();
    // Supabase returns UTC timestamps, convert to local
    if (!parsedTime.isUtc && rawTime.endsWith('Z')) {
      parsedTime = DateTime.parse(rawTime);
    }
    final localTime = parsedTime.toLocal();

    return UnfinishedRide(
      id: json['id']?.toString() ?? '',
      startTime: localTime,
      startLat: (json['start_lat'] as num?)?.toDouble(),
      startLon: (json['start_lon'] as num?)?.toDouble(),
    );
  }

  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(startTime);

    // Handle edge cases where diff might be negative (clock skew)
    if (diff.isNegative) {
      return 'Just now';
    }

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    } else {
      return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    }
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  bool _automatedMode = true; // Toggle state [RASD Table 4]
  late Future<DashboardStats> _statsFuture;
  List<UnfinishedRide> _unfinishedRides = [];

  // Offline sync support
  final LocalCacheService _cacheService = LocalCacheService.instance;
  StreamSubscription<int>? _pendingCountSub;
  int _pendingReportCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statsFuture = _fetchDashboardStats();
    _checkUnfinishedRides();
    _initOfflineListener();
  }

  void _initOfflineListener() {
    _pendingCountSub = _cacheService.pendingCountStream.listen((count) {
      if (mounted) {
        setState(() => _pendingReportCount = count);
      }
    });
  }

  @override
  void dispose() {
    _pendingCountSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStats();
      _checkUnfinishedRides();
    }
  }

  void _refreshStats() {
    setState(() {
      _statsFuture = _fetchDashboardStats();
    });
    _checkUnfinishedRides();
  }

  /// Check for rides that were started but never completed
  Future<void> _checkUnfinishedRides() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      setState(() {
        _unfinishedRides = [];
      });
      return;
    }

    try {
      // Fetch rides where completed is null/false AND end_time is null
      final rows =
          await client
                  .from('rides')
                  .select('id,start_time,start_lat,start_lon')
                  .eq('user_id', user.id)
                  .isFilter('end_time', null)
                  .order('start_time', ascending: false)
              as List<dynamic>;

      if (!mounted) return;
      setState(() {
        _unfinishedRides = rows
            .map((row) => UnfinishedRide.fromJson(row as Map<String, dynamic>))
            .toList();
      });
      debugPrint(
        'Dashboard: Found ${_unfinishedRides.length} unfinished rides',
      );
    } catch (e) {
      debugPrint('Dashboard: Failed to check unfinished rides: $e');
      if (mounted) {
        setState(() {
          _unfinishedRides = [];
        });
      }
    }
  }

  /// End a ride directly without going to the recording screen
  Future<void> _endUnfinishedRide(UnfinishedRide ride) async {
    try {
      // Only update end_time since 'completed' column may not exist
      await Supabase.instance.client
          .from('rides')
          .update({'end_time': DateTime.now().toIso8601String()})
          .eq('id', ride.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride ended successfully')),
        );
        _refreshStats();
      }
    } catch (e) {
      debugPrint('Failed to end ride: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to end ride: $e')));
      }
    }
  }

  /// Resume a ride - navigate to recording screen with ride data
  void _resumeUnfinishedRide(UnfinishedRide ride) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecordingScreen(resumeRideId: ride.id)),
    );
  }

  /// Show bottom sheet to manage unfinished rides
  void _showUnfinishedRidesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      color: Colors.orange,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'You have ${_unfinishedRides.length} unfinished ride${_unfinishedRides.length > 1 ? 's' : ''}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'These rides were started but never completed. You can resume or end them.',
                  style: TextStyle(color: Colors.grey, fontSize: 14),
                ),
                const SizedBox(height: 20),
                ..._unfinishedRides
                    .take(5)
                    .map((ride) => _buildUnfinishedRideCard(ride)),
                if (_unfinishedRides.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '+ ${_unfinishedRides.length - 5} more rides',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 16),
                // End All button
                if (_unfinishedRides.length > 1)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _endAllUnfinishedRides();
                      },
                      icon: const Icon(Icons.done_all, color: Colors.orange),
                      label: const Text('End All Rides'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnfinishedRideCard(UnfinishedRide ride) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.directions_bike,
              color: Colors.red,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Started ${ride.formattedTime}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'ID: ${ride.id.substring(0, 8)}...',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          // Resume button
          IconButton(
            onPressed: () {
              Navigator.pop(context);
              _resumeUnfinishedRide(ride);
            },
            icon: const Icon(Icons.play_arrow, color: Color(0xFF00FF00)),
            tooltip: 'Resume',
          ),
          // End button
          IconButton(
            onPressed: () {
              Navigator.pop(context);
              _endUnfinishedRide(ride);
            },
            icon: const Icon(Icons.stop, color: Colors.orange),
            tooltip: 'End now',
          ),
        ],
      ),
    );
  }

  Future<void> _endAllUnfinishedRides() async {
    final count = _unfinishedRides.length;
    try {
      for (final ride in _unfinishedRides) {
        await Supabase.instance.client
            .from('rides')
            .update({'end_time': DateTime.now().toIso8601String()})
            .eq('id', ride.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ended $count rides successfully')),
        );
        _refreshStats();
      }
    } catch (e) {
      debugPrint('Failed to end all rides: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to end rides: $e')));
      }
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const AuthScreen()));
    }
  }

  void _onNavTap(int index) {
    if (index == 0) return;
    final target = _navTarget(index);
    if (target == null) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => target));
  }

  Widget? _navTarget(int index) {
    switch (index) {
      case 1:
        return const RecordingScreen();
      case 2:
        return const HistoryScreen();
      case 3:
        return const ProfileScreen();
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final isGuest = user == null;
    final fallbackName = isGuest
        ? 'Guest'
        : _firstNameFromMeta(user.userMetadata, user.email);

    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Dark Mode
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: FutureBuilder<DashboardStats>(
          future: _statsFuture,
          builder: (context, snapshot) {
            final stats = snapshot.data;
            final displayName = isGuest
                ? 'Guest'
                : (stats?.displayName ?? fallbackName);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isGuest ? "Welcome," : "Welcome back,",
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
                Text(
                  displayName,
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              ],
            );
          },
        ),
        actions: [
          // Pending sync indicator
          if (_pendingReportCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_upload,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$_pendingReportCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!isGuest)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.grey),
              onPressed: _refreshStats,
            ),
          IconButton(
            icon: Icon(
              isGuest ? Icons.login : Icons.logout,
              color: Colors.grey,
            ),
            onPressed: _signOut,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: FutureBuilder<DashboardStats>(
          future: _statsFuture,
          builder: (context, snapshot) {
            final stats =
                snapshot.data ?? DashboardStats.fallback(fallbackName);

            return Column(
              children: [
                // Stats Row [DD Figure 12]
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCard(stats.totalDistanceText, "TOTAL DIST"),
                    _buildStatCard(stats.totalRidesText, "RIDES"),
                    _buildStatCard(stats.contributionText, "CONTRIBUTION"),
                  ],
                ),
                const Spacer(),

                // Big Start Button or "In A Ride" Button [DD 3.4.1]
                _buildMainActionButton(),

                const Spacer(),

                // Automated Sensor Toggle [DD Figure 12] - only for authenticated users
                if (!isGuest)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Automated Sensor Mode",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              "Passive quality detection",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _automatedMode,
                          activeColor: const Color(0xFF00FF00),
                          onChanged: (val) =>
                              setState(() => _automatedMode = val),
                        ),
                      ],
                    ),
                  ),

                // Guest mode info card
                if (isGuest)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF2196F3).withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Color(0xFF2196F3),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              "Guest Mode",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "View maps and routes. Sign in to record rides, report issues, and contribute to the community.",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const AuthScreen(),
                                ),
                                (route) => false,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00FF00),
                              foregroundColor: Colors.black,
                            ),
                            child: const Text('SIGN IN'),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
      // Bottom Nav [DD Figure 12]
      bottomNavigationBar: AppBottomNav(currentIndex: 0, onTap: _onNavTap),
    );
  }

  /// Build the main action button - shows "IN A RIDE" (red) if unfinished rides exist,
  /// "VIEW MAP" (blue) for guests, otherwise shows "START RIDE" (green)
  Widget _buildMainActionButton() {
    final user = Supabase.instance.client.auth.currentUser;
    final isGuest = user == null;
    final hasUnfinished = _unfinishedRides.isNotEmpty;

    // Guest mode - only allow viewing map (no recording)
    if (isGuest) {
      return GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const RecordingScreen(guestMode: true),
            ),
          );
        },
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3), // Blue for guest
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2196F3).withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map, color: Colors.white, size: 32),
                Text(
                  "VIEW\nMAP",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        if (hasUnfinished) {
          _showUnfinishedRidesSheet();
        } else {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const RecordingScreen()));
        }
      },
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          color: hasUnfinished ? Colors.red : const Color(0xFF00FF00),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (hasUnfinished ? Colors.red : const Color(0xFF00FF00))
                  .withOpacity(0.4),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasUnfinished)
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              Text(
                hasUnfinished ? "IN A\nRIDE" : "START\nRIDE",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: hasUnfinished ? Colors.white : Colors.black,
                ),
              ),
              if (hasUnfinished && _unfinishedRides.length > 1)
                Text(
                  "(${_unfinishedRides.length})",
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF00FF00),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Future<DashboardStats> _fetchDashboardStats() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      return DashboardStats.fallback("Cyclist");
    }

    String? fullName = _firstNameFromMeta(user.userMetadata, user.email);
    double totalDistanceKm = 0;

    // Get user's full name from profile
    try {
      final profile = await client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null) {
        fullName = _firstNameFromMeta({
          'full_name': profile['full_name'],
        }, fullName);
      }
    } catch (_) {}

    // ALWAYS calculate total distance from rides - using distance_km or coordinates
    try {
      final allRides =
          await client
                  .from('rides')
                  .select('id,distance_km,start_lat,start_lon,end_lat,end_lon')
                  .eq('user_id', user.id)
              as List<dynamic>;

      double sumDistance = 0;
      int ridesWithStoredDistance = 0;
      int ridesCalculatedFromCoords = 0;

      debugPrint(
        'Dashboard: Found ${allRides.length} rides for user ${user.id}',
      );

      for (final ride in allRides) {
        final storedDist = _toDouble(ride['distance_km']);

        // Use stored distance_km if available and > 0
        if (storedDist != null && storedDist > 0.01) {
          sumDistance += storedDist;
          ridesWithStoredDistance++;
          debugPrint(
            'Dashboard: Ride ${ride['id']} - stored distance: ${storedDist.toStringAsFixed(2)} km',
          );
        } else {
          // Fallback: calculate from start/end coordinates
          final startLat = _toDouble(ride['start_lat']);
          final startLon = _toDouble(ride['start_lon']);
          final endLat = _toDouble(ride['end_lat']);
          final endLon = _toDouble(ride['end_lon']);

          if (startLat != null &&
              startLon != null &&
              endLat != null &&
              endLon != null) {
            final calcDist = _calculateDistanceKm(
              startLat,
              startLon,
              endLat,
              endLon,
            );
            if (calcDist > 0.01) {
              sumDistance += calcDist;
              ridesCalculatedFromCoords++;
              debugPrint(
                'Dashboard: Ride ${ride['id']} - calculated from coords: ${calcDist.toStringAsFixed(2)} km',
              );
            }
          }
        }
      }

      totalDistanceKm = sumDistance;
      debugPrint(
        'Dashboard: TOTAL distance: ${sumDistance.toStringAsFixed(2)} km '
        '($ridesWithStoredDistance with stored, $ridesCalculatedFromCoords calculated from coords)',
      );
    } catch (e) {
      debugPrint('Dashboard: Failed to calculate total distance: $e');
    }

    // Always fetch live ride count from rides table
    int totalRides = 0;
    int anomalyCount = 0;
    try {
      final rides =
          await client.from('rides').select('id').eq('user_id', user.id)
              as List<dynamic>;
      totalRides = rides.length;
      debugPrint(
        'Dashboard: Fetched ${rides.length} rides for user ${user.id}',
      );
    } catch (e) {
      debugPrint('Dashboard: Failed to fetch rides: $e');
    }

    try {
      final anomalies =
          await client.from('anomalies').select('id').eq('user_id', user.id)
              as List<dynamic>;
      anomalyCount = anomalies.length;
      debugPrint('Dashboard: Fetched $anomalyCount anomalies');
    } catch (e) {
      debugPrint('Dashboard: Failed to fetch anomalies: $e');
    }

    return DashboardStats(
      displayName: fullName ?? "Cyclist",
      totalDistanceKm: totalDistanceKm,
      totalRides: totalRides,
      contributionCount: anomalyCount,
    );
  }

  String _firstNameFromMeta(Map<String, dynamic>? metadata, String? fallback) {
    final fullName = (metadata?['full_name'] ?? metadata?['fullName'])
        ?.toString();
    final nameSource = fullName ?? fallback ?? "Cyclist";
    final trimmed = nameSource.trim();
    if (trimmed.isEmpty) return "Cyclist";
    return trimmed.split(RegExp(r'\s+')).first;
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Calculate distance between two coordinates using Haversine formula
  double _calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371; // km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;
}

class DashboardStats {
  final String displayName;
  final double totalDistanceKm;
  final int totalRides;
  final int contributionCount;

  const DashboardStats({
    required this.displayName,
    required this.totalDistanceKm,
    required this.totalRides,
    required this.contributionCount,
  });

  String get totalDistanceText => "${totalDistanceKm.toStringAsFixed(1)}km";
  String get totalRidesText => totalRides.toString();
  String get contributionText => contributionCount.toString();

  static DashboardStats fallback(String displayName) {
    return DashboardStats(
      displayName: displayName,
      totalDistanceKm: 0,
      totalRides: 0,
      contributionCount: 0,
    );
  }
}
