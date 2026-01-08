import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'recording_screen.dart';

class RideSummaryScreen extends StatefulWidget {
  final List<LatLng> routePoints;
  final List<PotholeReport> reports;
  final LatLng startPoint;
  final LatLng endPoint;
  final Duration rideDuration;

  const RideSummaryScreen({
    super.key,
    required this.routePoints,
    required this.reports,
    required this.startPoint,
    required this.endPoint,
    required this.rideDuration,
  });

  @override
  State<RideSummaryScreen> createState() => _RideSummaryScreenState();
}

class _RideSummaryScreenState extends State<RideSummaryScreen> {
  late List<PotholeReport> _autoReports;
  late List<PotholeReport> _manualReports;
  late double _distanceKm;
  late double _avgSpeedKmh;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _autoReports = widget.reports.where((r) => !r.isManual).toList();
    _manualReports = widget.reports.where((r) => r.isManual).toList();
    _distanceKm = _computeDistanceKm(widget.routePoints);
    _avgSpeedKmh = _computeAverageSpeed();
  }

  Future<void> _saveAndPublish() async {
    if (_saving) return;

    final confirmedAuto = _autoReports.where((r) => r.isVerified).toList();
    for (final manual in _manualReports) {
      manual.isVerified = true; // manual reports are always accepted
    }
    final toSave = [..._manualReports, ...confirmedAuto];

    if (toSave.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nothing to publish yet.')),
        );
      }
      return;
    }

    setState(() => _saving = true);

    try {
      for (final report in toSave) {
        await Supabase.instance.client.from('anomalies').insert({
          'lat': report.location.latitude,
          'lng': report.location.longitude,
          'ride_active': true,
          'type': report.isManual ? 'manual' : 'auto',
          'category': report.category,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${toSave.length} reports.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to publish: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Ride Summary'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStat('${_distanceKm.toStringAsFixed(2)} km', 'Distance', const Color(0xFF00FF00)),
                _buildStat(_formatDuration(widget.rideDuration), 'Time', const Color(0xFF00FF00)),
                _buildStat('${_avgSpeedKmh.toStringAsFixed(1)} km/h', 'Avg Speed', const Color(0xFF00FF00)),
              ],
            ),
          ),
          _sectionHeader('VERIFY SENSOR DETECTIONS'),
          Expanded(
            child: ListView(
              children: [
                if (_autoReports.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Text(
                      'No sensor detections this ride.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ..._autoReports.map(_buildAutoTile),
                if (_manualReports.isNotEmpty) ...[
                  _sectionHeader('MANUAL REPORTS (AUTO-SAVED)'),
                  ..._manualReports.map(_buildManualTile),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveAndPublish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _saving ? 'SAVING...' : 'SAVE & PUBLISH',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _computeDistanceKm(List<LatLng> points) {
    if (points.length < 2) return 0;
    final dist = const Distance();
    double km = 0;
    for (int i = 0; i < points.length - 1; i++) {
      km += dist.as(LengthUnit.Kilometer, points[i], points[i + 1]);
    }
    return km;
  }

  double _computeAverageSpeed() {
    final seconds = widget.rideDuration.inSeconds;
    if (seconds == 0) return 0;
    return _distanceKm / (seconds / 3600);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 10, top: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildAutoTile(PotholeReport report) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.category,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Text(
                  'Auto-Detected',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          if (!report.isVerified) ...[
            const CircleAvatar(
              backgroundColor: Colors.red,
              child: Icon(Icons.close, color: Colors.white),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () => setState(() => report.isVerified = true),
              child: const CircleAvatar(
                backgroundColor: Colors.grey,
                child: Icon(Icons.check, color: Colors.black),
              ),
            ),
          ] else ...[
            GestureDetector(
              onTap: () => setState(() => report.isVerified = false),
              child: const CircleAvatar(
                backgroundColor: Colors.grey,
                child: Icon(Icons.close, color: Colors.black),
              ),
            ),
            const SizedBox(width: 10),
            const CircleAvatar(
              backgroundColor: Color(0xFF00FF00),
              child: Icon(Icons.check, color: Colors.black),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManualTile(PotholeReport report) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit, color: Colors.orange),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.category,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Text(
                  'Manual Report (auto-saved)',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          const CircleAvatar(
            backgroundColor: Color(0xFF00FF00),
            child: Icon(Icons.check, color: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }
}
