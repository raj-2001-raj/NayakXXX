import 'dart:math';
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
    double totalDistanceKm = 0;
    int? totalRides;
    int? contributionCount;

    // Fetch full name from profile
    try {
      final profile = await client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();
      if (profile != null) {
        fullName = profile['full_name']?.toString() ?? fullName;
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
        '[PROFILE] Found ${allRides.length} rides for user ${user.id}',
      );

      for (final ride in allRides) {
        final storedDist = _toDouble(ride['distance_km']);

        // Use stored distance_km if available and > 0
        if (storedDist != null && storedDist > 0.01) {
          sumDistance += storedDist;
          ridesWithStoredDistance++;
          debugPrint(
            '[PROFILE] Ride ${ride['id']} - stored distance: ${storedDist.toStringAsFixed(2)} km',
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
                '[PROFILE] Ride ${ride['id']} - calculated from coords: ${calcDist.toStringAsFixed(2)} km',
              );
            }
          }
        }
      }

      totalDistanceKm = sumDistance;
      debugPrint(
        '[PROFILE] TOTAL distance: ${sumDistance.toStringAsFixed(2)} km '
        '($ridesWithStoredDistance with stored, $ridesCalculatedFromCoords calculated from coords)',
      );
    } catch (e) {
      debugPrint('[PROFILE] Failed to calculate total distance: $e');
    }

    // Get actual ride count from rides table
    try {
      final rides =
          await client.from('rides').select('id').eq('user_id', user.id)
              as List<dynamic>;
      totalRides = rides.length;
      debugPrint('[PROFILE] Fetched ${rides.length} rides from rides table');
    } catch (e) {
      debugPrint('[PROFILE] Error fetching rides: $e');
      totalRides = 0;
    }

    // Get contribution count (total anomalies reported)
    try {
      final anomalies =
          await client.from('anomalies').select('id').eq('user_id', user.id)
              as List<dynamic>;
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
      totalDistanceKm: totalDistanceKm,
      totalRides: totalRides,
      scoreLabel: '$contributionCount',
    );
  }

  void _onNavTap(int index) {
    if (index == 3) return;
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

  Widget _buildGuestMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 64, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            const Text(
              'Sign in to access your profile',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create an account to track your rides, report hazards, and contribute to the cycling community.',
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
        title: const Text('Profile'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isGuest
          ? _buildGuestMessage()
          : FutureBuilder<ProfileDetails>(
              future: _profileFuture,
              builder: (context, snapshot) {
                final details = snapshot.data ?? const ProfileDetails.empty();
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _ProfileHeader(
                      name: details.fullName,
                      email: details.email,
                    ),
                    const SizedBox(height: 20),
                    _InfoTile(label: 'User ID', value: details.userId),
                    _InfoTile(
                      label: 'Total Distance',
                      value: '${details.totalDistanceKm.toStringAsFixed(1)} km',
                    ),
                    _InfoTile(
                      label: 'Total Rides',
                      value: details.totalRides.toString(),
                    ),
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
      bottomNavigationBar: AppBottomNav(currentIndex: 3, onTap: _onNavTap),
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

  /// Calculate distance between two coordinates using Haversine formula
  double _calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371; // Earth's radius in kilometers
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
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
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
