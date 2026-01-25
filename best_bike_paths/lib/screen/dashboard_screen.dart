import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'recording_screen.dart'; // This is your Map screen (renamed)
import 'auth_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import 'app_bottom_nav.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  bool _automatedMode = true; // Toggle state [RASD Table 4]
  late Future<DashboardStats> _statsFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statsFuture = _fetchDashboardStats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStats();
    }
  }

  void _refreshStats() {
    setState(() {
      _statsFuture = _fetchDashboardStats();
    });
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => target),
    );
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
    final fallbackName = _firstNameFromMeta(user?.userMetadata, user?.email);

    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Dark Mode
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: FutureBuilder<DashboardStats>(
          future: _statsFuture,
          builder: (context, snapshot) {
            final stats = snapshot.data;
            final displayName = stats?.displayName ?? fallbackName;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Welcome back,",
                  style: TextStyle(color: Colors.grey, fontSize: 14),
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
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            onPressed: _refreshStats,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.grey),
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

                // Big Start Button [DD 3.4.1]
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RecordingScreen(),
                      ),
                    );
                  },
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FF00),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FF00).withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        "START\nRIDE",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // Automated Sensor Toggle [DD Figure 12]
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
                            style: TextStyle(color: Colors.grey, fontSize: 12),
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
                const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
      // Bottom Nav [DD Figure 12]
      bottomNavigationBar: AppBottomNav(
        currentIndex: 0,
        onTap: _onNavTap,
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
    double? totalDistanceKm;

    try {
      final profile = await client
          .from('profiles')
          .select('full_name,total_distance_km')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null) {
        fullName = _firstNameFromMeta({
          'full_name': profile['full_name'],
        }, fullName);
        totalDistanceKm = _toDouble(profile['total_distance_km']);
      }
    } catch (_) {}

    if (totalDistanceKm == null) {
      try {
        final stats = await client
            .from('user_stats')
            .select('total_distance_km')
            .eq('user_id', user.id)
            .maybeSingle();
        if (stats != null) {
          totalDistanceKm ??= _toDouble(stats['total_distance_km']);
        }
      } catch (_) {}
    }

    // Always fetch live ride count from rides table
    int totalRides = 0;
    int anomalyCount = 0;
    try {
      final rides = await client
          .from('rides')
          .select('id')
          .eq('user_id', user.id) as List<dynamic>;
      totalRides = rides.length;
      debugPrint('Dashboard: Fetched ${rides.length} rides for user ${user.id}');
    } catch (e) {
      debugPrint('Dashboard: Failed to fetch rides: $e');
    }

    try {
      final anomalies = await client
          .from('anomalies')
          .select('id')
          .eq('user_id', user.id) as List<dynamic>;
      anomalyCount = anomalies.length;
      debugPrint('Dashboard: Fetched $anomalyCount anomalies');
    } catch (e) {
      debugPrint('Dashboard: Failed to fetch anomalies: $e');
    }

    return DashboardStats(
      displayName: fullName ?? "Cyclist",
      totalDistanceKm: totalDistanceKm ?? 0,
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
