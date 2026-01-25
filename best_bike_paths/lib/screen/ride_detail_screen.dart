import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RideDetailScreen extends StatefulWidget {
  final String rideId;

  const RideDetailScreen({super.key, required this.rideId});

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  late final Future<RideDetailData> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = _fetchDetails();
  }

  Future<RideDetailData> _fetchDetails() async {
    final client = Supabase.instance.client;
    RideHistoryEntry? ride;
    List<AnomalyEntry> anomalies = [];

    try {
      final row = await client
          .from('rides')
          .select(
            'id,start_time,end_time,start_lat,start_lon,end_lat,end_lon,completed,reached_destination',
          )
          .eq('id', widget.rideId)
          .maybeSingle();
      if (row != null) {
        ride = RideHistoryEntry.fromJson(row);
      }
    } catch (_) {
      try {
        final row = await client
            .from('rides')
            .select('id,start_time,end_time,start_lat,start_lon')
            .eq('id', widget.rideId)
            .maybeSingle();
        if (row != null) {
          ride = RideHistoryEntry.fromJson(row);
        }
      } catch (_) {}
    }

    try {
      final rows = await client
          .from('anomalies')
          .select('id,category,type,severity,verified,created_at')
          .eq('ride_id', widget.rideId)
          .order('created_at', ascending: true) as List<dynamic>;
      anomalies = rows.map((row) => AnomalyEntry.fromJson(row)).toList();
    } catch (_) {}

    return RideDetailData(ride: ride, anomalies: anomalies);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Ride Details'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: FutureBuilder<RideDetailData>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data ?? const RideDetailData();
          final ride = data.ride;
          if (ride == null) {
            return const Center(
              child: Text(
                'Ride not found.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _RideHeader(ride: ride),
              const SizedBox(height: 16),
              if (ride.startPoint != null)
                _RideMapCard(
                  start: ride.startPoint!,
                  end: ride.endPoint,
                ),
              if (ride.startPoint != null) const SizedBox(height: 16),
              _InfoCard(
                title: 'Summary',
                children: [
                  _InfoRow(label: 'Ride ID', value: ride.id),
                  _InfoRow(
                    label: 'Start',
                    value: ride.startPoint != null
                        ? _formatLatLng(ride.startPoint!)
                        : 'Unknown',
                  ),
                  _InfoRow(
                    label: 'End',
                    value: ride.endPoint != null
                        ? _formatLatLng(ride.endPoint!)
                        : 'Unknown',
                  ),
                  _InfoRow(
                    label: 'Duration',
                    value: ride.duration != null
                        ? _formatDuration(ride.duration!)
                        : '-',
                  ),
                  _InfoRow(
                    label: 'Distance',
                    value: ride.distanceKm != null
                        ? '${ride.distanceKm!.toStringAsFixed(2)} km (straight-line)'
                        : '-',
                  ),
                  _InfoRow(
                    label: 'Avg speed',
                    value: ride.avgSpeedKmh != null
                        ? '${ride.avgSpeedKmh!.toStringAsFixed(1)} km/h'
                        : '-',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InfoCard(
                title: 'Anomalies (${data.anomalies.length})',
                children: data.anomalies.isEmpty
                    ? [
                        const Text(
                          'No anomalies reported for this ride.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ]
                    : data.anomalies
                        .map((a) => _AnomalyTile(anomaly: a))
                        .toList(),
              ),
            ],
          );
        },
      ),
    );
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

class RideDetailData {
  final RideHistoryEntry? ride;
  final List<AnomalyEntry> anomalies;

  const RideDetailData({this.ride, this.anomalies = const []});
}

class RideHistoryEntry {
  final String id;
  final DateTime? startTime;
  final DateTime? endTime;
  final LatLng? startPoint;
  final LatLng? endPoint;
  final bool? completed;
  final bool? reachedDestination;

  const RideHistoryEntry({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.startPoint,
    required this.endPoint,
    required this.completed,
    required this.reachedDestination,
  });

  factory RideHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RideHistoryEntry(
      id: json['id']?.toString() ?? '-',
      startTime: _parseDate(json['start_time']),
      endTime: _parseDate(json['end_time']),
      startPoint: _parseLatLng(json['start_lat'], json['start_lon']),
      endPoint: _parseLatLng(json['end_lat'], json['end_lon']),
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

  double? get distanceKm {
    if (startPoint == null || endPoint == null) return null;
    return const Distance().as(LengthUnit.Kilometer, startPoint!, endPoint!);
  }

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

class AnomalyEntry {
  final String id;
  final String category;
  final String type;
  final String severity;
  final bool verified;
  final DateTime? createdAt;

  const AnomalyEntry({
    required this.id,
    required this.category,
    required this.type,
    required this.severity,
    required this.verified,
    required this.createdAt,
  });

  factory AnomalyEntry.fromJson(Map<String, dynamic> json) {
    return AnomalyEntry(
      id: json['id']?.toString() ?? '-',
      category: json['category']?.toString() ?? 'Unknown',
      type: json['type']?.toString() ?? '-',
      severity: json['severity']?.toString() ?? '-',
      verified: json['verified'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

class _RideHeader extends StatelessWidget {
  final RideHistoryEntry ride;

  const _RideHeader({required this.ride});

  @override
  Widget build(BuildContext context) {
    final dateLabel = ride.startTime != null
        ? _formatDateTime(ride.startTime!)
        : 'Unknown start';
  final statusLabel = ride.endTime == null && !ride.isStaleWithoutEnd
    ? 'In progress'
    : ride.isEndedEarly || ride.isStaleWithoutEnd
      ? 'Early terminated'
      : 'Finished';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_bike, color: Color(0xFF00FF00), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statusLabel,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
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
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _RideMapCard extends StatelessWidget {
  final LatLng start;
  final LatLng? end;

  const _RideMapCard({required this.start, this.end});

  @override
  Widget build(BuildContext context) {
    final hasEnd = end != null;
    final points = [start, if (hasEnd) end!];
    final bounds = LatLngBounds.fromPoints(points);
    final hasDistinctPoints = hasEnd &&
        (start.latitude != end!.latitude || start.longitude != end!.longitude);

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: start,
            initialZoom: 13,
            initialCameraFit: hasDistinctPoints
                ? CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(24),
                  )
                : null,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.example.bbp.best_bike_paths',
            ),
            PolylineLayer(
              polylines: [
                if (hasEnd)
                  Polyline(
                    points: [start, end!],
                    strokeWidth: 3,
                    color: const Color(0xFF00FF00),
                  ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: start,
                  width: 30,
                  height: 30,
                  child: const Icon(Icons.flag, color: Colors.blue, size: 26),
                ),
                if (hasEnd)
                  Marker(
                    point: end!,
                    width: 30,
                    height: 30,
                    child:
                        const Icon(Icons.location_on, color: Colors.red, size: 28),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
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

class _AnomalyTile extends StatelessWidget {
  final AnomalyEntry anomaly;

  const _AnomalyTile({required this.anomaly});

  @override
  Widget build(BuildContext context) {
    final severity = anomaly.severity.isEmpty ? '-' : anomaly.severity;
    final category = anomaly.category.isEmpty ? '-' : anomaly.category;
    final type = anomaly.type.isEmpty ? '-' : anomaly.type;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2C),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                category,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                anomaly.verified ? 'Verified' : 'Unverified',
                style: TextStyle(
                  color: anomaly.verified ? const Color(0xFF00FF00) : Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Type: $type',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          Text(
            'Severity: $severity',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          if (anomaly.createdAt != null)
            Text(
              'Recorded: ${_formatDateTime(anomaly.createdAt!)}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
        ],
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
}
