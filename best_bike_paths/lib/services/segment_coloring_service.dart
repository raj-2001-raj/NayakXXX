import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Represents a road segment with its safety score
class RoadSegment {
  final List<LatLng> points;
  final double safetyScore; // 0.0 (dangerous) to 1.0 (safe)
  final int anomalyCount;
  final String? dominantCategory;

  const RoadSegment({
    required this.points,
    required this.safetyScore,
    required this.anomalyCount,
    this.dominantCategory,
  });

  /// Get color based on safety score
  Color get color {
    if (safetyScore >= 0.8) {
      return Colors.green; // Safe - Optimal
    } else if (safetyScore >= 0.6) {
      return Colors.lightGreen; // Mostly safe
    } else if (safetyScore >= 0.4) {
      return Colors.yellow; // Caution
    } else if (safetyScore >= 0.2) {
      return Colors.orange; // Warning
    } else {
      return Colors.red; // Hazardous
    }
  }

  /// Get label for this segment's condition
  String get conditionLabel {
    if (safetyScore >= 0.8) return 'Optimal';
    if (safetyScore >= 0.6) return 'Good';
    if (safetyScore >= 0.4) return 'Fair';
    if (safetyScore >= 0.2) return 'Poor';
    return 'Hazardous';
  }
}

/// Service for computing segment safety scores and colors
class SegmentColoringService {
  static const double _segmentLengthMeters =
      100; // Split routes into 100m segments
  static const double _anomalyInfluenceRadius =
      50; // Anomalies within 50m affect segment
  static const Distance _distance = Distance();

  /// Split a route into colored segments based on nearby anomalies
  static List<RoadSegment> computeColoredSegments(
    List<LatLng> routePoints,
    List<AnomalyData> anomalies,
  ) {
    if (routePoints.length < 2) return [];

    final segments = <RoadSegment>[];
    List<LatLng> currentSegment = [routePoints[0]];
    double accumulatedDistance = 0;

    for (int i = 1; i < routePoints.length; i++) {
      final prevPoint = routePoints[i - 1];
      final currPoint = routePoints[i];
      final segmentDist = _distance.as(LengthUnit.Meter, prevPoint, currPoint);

      accumulatedDistance += segmentDist;
      currentSegment.add(currPoint);

      // When we've accumulated enough distance, create a segment
      if (accumulatedDistance >= _segmentLengthMeters ||
          i == routePoints.length - 1) {
        final score = _computeSegmentScore(currentSegment, anomalies);
        final nearbyAnomalies = _countNearbyAnomalies(
          currentSegment,
          anomalies,
        );
        final dominantCat = _getDominantCategory(currentSegment, anomalies);

        segments.add(
          RoadSegment(
            points: List.from(currentSegment),
            safetyScore: score,
            anomalyCount: nearbyAnomalies,
            dominantCategory: dominantCat,
          ),
        );

        // Start new segment from the last point
        currentSegment = [currPoint];
        accumulatedDistance = 0;
      }
    }

    return segments;
  }

  /// Compute safety score for a segment based on nearby anomalies
  static double _computeSegmentScore(
    List<LatLng> segmentPoints,
    List<AnomalyData> anomalies,
  ) {
    if (anomalies.isEmpty) return 1.0; // No anomalies = perfectly safe

    double totalWeight = 0;
    final segmentCenter = _getSegmentCenter(segmentPoints);

    for (final anomaly in anomalies) {
      final dist = _distance.as(
        LengthUnit.Meter,
        segmentCenter,
        anomaly.location,
      );

      if (dist <= _anomalyInfluenceRadius) {
        // Weight decreases with distance
        final distanceWeight = 1 - (dist / _anomalyInfluenceRadius);
        // Severity affects weight
        final severityWeight = anomaly.severity;
        // Verified anomalies have more weight
        final verifiedWeight = anomaly.verified ? 1.5 : 1.0;

        totalWeight += distanceWeight * severityWeight * verifiedWeight;
      }
    }

    // Convert weight to score (inverse relationship)
    // More anomaly weight = lower safety score
    final score = 1.0 - (totalWeight / 5.0).clamp(0.0, 1.0);
    return score;
  }

  /// Count anomalies near a segment
  static int _countNearbyAnomalies(
    List<LatLng> segmentPoints,
    List<AnomalyData> anomalies,
  ) {
    final segmentCenter = _getSegmentCenter(segmentPoints);
    int count = 0;

    for (final anomaly in anomalies) {
      final dist = _distance.as(
        LengthUnit.Meter,
        segmentCenter,
        anomaly.location,
      );
      if (dist <= _anomalyInfluenceRadius) {
        count++;
      }
    }

    return count;
  }

  /// Get the most common anomaly category near a segment
  static String? _getDominantCategory(
    List<LatLng> segmentPoints,
    List<AnomalyData> anomalies,
  ) {
    final segmentCenter = _getSegmentCenter(segmentPoints);
    final categoryCounts = <String, int>{};

    for (final anomaly in anomalies) {
      final dist = _distance.as(
        LengthUnit.Meter,
        segmentCenter,
        anomaly.location,
      );
      if (dist <= _anomalyInfluenceRadius) {
        categoryCounts[anomaly.category] =
            (categoryCounts[anomaly.category] ?? 0) + 1;
      }
    }

    if (categoryCounts.isEmpty) return null;

    // Find category with most occurrences
    String? dominant;
    int maxCount = 0;
    categoryCounts.forEach((category, count) {
      if (count > maxCount) {
        maxCount = count;
        dominant = category;
      }
    });

    return dominant;
  }

  /// Get the center point of a segment
  static LatLng _getSegmentCenter(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(0, 0);
    if (points.length == 1) return points[0];

    double totalLat = 0;
    double totalLon = 0;
    for (final point in points) {
      totalLat += point.latitude;
      totalLon += point.longitude;
    }
    return LatLng(totalLat / points.length, totalLon / points.length);
  }

  /// Generate a legend for the color coding
  static List<ColorLegendItem> getLegend() {
    return const [
      ColorLegendItem(
        color: Colors.green,
        label: 'Optimal',
        description: 'Safe path',
      ),
      ColorLegendItem(
        color: Colors.lightGreen,
        label: 'Good',
        description: 'Minor issues',
      ),
      ColorLegendItem(
        color: Colors.yellow,
        label: 'Fair',
        description: 'Some hazards',
      ),
      ColorLegendItem(
        color: Colors.orange,
        label: 'Poor',
        description: 'Multiple hazards',
      ),
      ColorLegendItem(
        color: Colors.red,
        label: 'Hazardous',
        description: 'Avoid if possible',
      ),
    ];
  }
}

/// Anomaly data for segment scoring
class AnomalyData {
  final LatLng location;
  final double severity; // 0.0 to 1.0
  final String category;
  final bool verified;

  const AnomalyData({
    required this.location,
    required this.severity,
    required this.category,
    required this.verified,
  });

  factory AnomalyData.fromJson(Map<String, dynamic> json) {
    // Parse location
    LatLng location;
    if (json['location'] is String) {
      // PostGIS format: "POINT(lon lat)" or "SRID=4326;POINT(lon lat)"
      final locStr = json['location'] as String;
      final match = RegExp(
        r'POINT\(([-\d.]+)\s+([-\d.]+)\)',
      ).firstMatch(locStr);
      if (match != null) {
        final lon = double.tryParse(match.group(1)!) ?? 0;
        final lat = double.tryParse(match.group(2)!) ?? 0;
        location = LatLng(lat, lon);
      } else {
        location = const LatLng(0, 0);
      }
    } else if (json['latitude'] != null && json['longitude'] != null) {
      location = LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      );
    } else {
      location = const LatLng(0, 0);
    }

    // Parse severity (could be numeric 1-5 or 0.0-1.0)
    double severity = 0.5;
    if (json['severity'] != null) {
      final sev = (json['severity'] as num).toDouble();
      if (sev > 1) {
        // Assume 1-5 scale, normalize to 0-1
        severity = (sev / 5.0).clamp(0.0, 1.0);
      } else {
        severity = sev.clamp(0.0, 1.0);
      }
    }

    return AnomalyData(
      location: location,
      severity: severity,
      category: json['category']?.toString() ?? 'Unknown',
      verified: json['verified'] == true,
    );
  }
}

/// Legend item for UI display
class ColorLegendItem {
  final Color color;
  final String label;
  final String description;

  const ColorLegendItem({
    required this.color,
    required this.label,
    required this.description,
  });
}
