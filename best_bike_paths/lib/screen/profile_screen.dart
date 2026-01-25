import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_bottom_nav.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'recording_screen.dart';
import 'auth_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final Future<ProfileDetails> _profileFuture;
  bool _avoidCobblestones = false;
  bool _showFountains = true;

  @override
  void initState() {
    super.initState();
    _profileFuture = _fetchProfile();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _avoidCobblestones = prefs.getBool('avoid_cobblestones') ?? false;
      _showFountains = prefs.getBool('show_fountains') ?? true;
    });
  }

  Future<void> _updatePreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<ProfileDetails> _fetchProfile() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      return const ProfileDetails.empty();
    }

    String? fullName = _firstNameFromMeta(user.userMetadata, user.email);
    double? totalDistanceKm;
    int? totalRides;
    int? contributionCount;

    // Fetch full name and distance from profile
    try {
      final profile = await client
          .from('profiles')
          .select('full_name,total_distance_km')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null) {
        fullName = profile['full_name']?.toString() ?? fullName;
        totalDistanceKm = _toDouble(profile['total_distance_km']);
      }
    } catch (_) {}

    // Fallback for distance from user_stats
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

    // Get actual ride count from rides table
    try {
      final rides = await client
          .from('rides')
          .select('id')
          .eq('user_id', user.id) as List<dynamic>;
      totalRides = rides.length;
      debugPrint('[PROFILE] Fetched ${rides.length} rides from rides table');
    } catch (e) {
      debugPrint('[PROFILE] Error fetching rides: $e');
      totalRides = 0;
    }

    // Get contribution count (total anomalies reported)
    try {
      final anomalies = await client
          .from('anomalies')
          .select('id')
          .eq('user_id', user.id) as List<dynamic>;
      contributionCount = anomalies.length;
      debugPrint('[PROFILE] Fetched $contributionCount anomalies');
    } catch (e) {
      debugPrint('[PROFILE] Error fetching anomalies: $e');
      contributionCount = 0;
    }

    return ProfileDetails(
      userId: user.id,
      email: user.email,
      fullName: fullName ?? 'Cyclist',
      totalDistanceKm: totalDistanceKm ?? 0,
      totalRides: totalRides,
      scoreLabel: '$contributionCount',
    );
  }

  void _onNavTap(int index) {
    if (index == 3) return;
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
      case 1:
        return const RecordingScreen();
      case 2:
        return const HistoryScreen();
      default:
        return null;
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<ProfileDetails>(
        future: _profileFuture,
        builder: (context, snapshot) {
          final details = snapshot.data ?? const ProfileDetails.empty();
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _ProfileHeader(name: details.fullName, email: details.email),
              const SizedBox(height: 20),
              _InfoTile(label: 'User ID', value: details.userId),
              _InfoTile(
                label: 'Total Distance',
                value: '${details.totalDistanceKm.toStringAsFixed(1)} km',
              ),
              _InfoTile(label: 'Total Rides', value: details.totalRides.toString()),
              _InfoTile(label: 'Score', value: details.scoreLabel),
              const SizedBox(height: 20),
              const Text(
                'Map preferences',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 10),
              _PreferenceTile(
                label: 'Avoid cobblestones',
                subtitle: 'Prefer smoother surfaces when routing',
                value: _avoidCobblestones,
                onChanged: (value) {
                  setState(() => _avoidCobblestones = value);
                  _updatePreference('avoid_cobblestones', value);
                },
              ),
              _PreferenceTile(
                label: 'Show water fountains',
                subtitle: 'Display nearby fountains on the map',
                value: _showFountains,
                onChanged: (value) {
                  setState(() => _showFountains = value);
                  _updatePreference('show_fountains', value);
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 3,
        onTap: _onNavTap,
      ),
    );
  }

  String _firstNameFromMeta(Map<String, dynamic>? metadata, String? fallback) {
    final fullName = (metadata?['full_name'] ?? metadata?['fullName'])
        ?.toString();
    final nameSource = fullName ?? fallback ?? 'Cyclist';
    final trimmed = nameSource.trim();
    if (trimmed.isEmpty) return 'Cyclist';
    return trimmed;
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class ProfileDetails {
  final String userId;
  final String? email;
  final String fullName;
  final double totalDistanceKm;
  final int totalRides;
  final String scoreLabel;

  const ProfileDetails({
    required this.userId,
    required this.email,
    required this.fullName,
    required this.totalDistanceKm,
    required this.totalRides,
    required this.scoreLabel,
  });

  const ProfileDetails.empty()
      : userId = '-',
        email = null,
        fullName = 'Cyclist',
        totalDistanceKm = 0,
        totalRides = 0,
        scoreLabel = '-';
}

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String? email;

  const _ProfileHeader({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xFF00FF00),
            child: Icon(Icons.person, color: Colors.black, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email ?? 'No email',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PreferenceTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: const Color(0xFF00FF00),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
