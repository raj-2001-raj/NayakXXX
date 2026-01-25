import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class NavigationService {
  // 1. Search for Places (Nominatim API)
  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    if (query.length < 3) return []; // Don't search for "a" or "ab"

    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5',
    );

    try {
      final response = await http.get(
        url,
        headers: {'User-Agent': 'BestBikePaths_StudentProject'},
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
    } catch (_) {}
    return [];
  }

  // 2. Get Bike Routes (OSRM API)
  Future<List<BikeRouteOption>> getBikeRoutes(
    LatLng start,
    LatLng end, {
    int maxRoutes = 5,
  }) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/bicycle/'
      '${start.longitude},${start.latitude};'
      '${end.longitude},${end.latitude}'
      '?overview=full&geometries=geojson&alternatives=true',
    );

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = (data['routes'] as List?) ?? [];

        return routes.take(maxRoutes).map((route) {
          final geometry = route['geometry']['coordinates'] as List;
          final points = geometry
              .map((coord) => LatLng(coord[1].toDouble(), coord[0].toDouble()))
              .toList();
          
          final distanceMeters = (route['distance'] as num).toDouble();
          var durationSeconds = (route['duration'] as num).toDouble();
          
          // Sanity check: OSRM may return unrealistic times
          // For cycling, average speed is 12-18 km/h (urban with stops: ~12 km/h)
          // If OSRM returns faster than 20 km/h avg, use our own estimate
          final avgSpeedKmh = (distanceMeters / 1000) / (durationSeconds / 3600);
          if (avgSpeedKmh > 20 || durationSeconds <= 0) {
            // Calculate based on realistic cycling speed of 15 km/h
            durationSeconds = (distanceMeters / 1000) / 15 * 3600;
          }
          
          return BikeRouteOption(
            points: points,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
          );
        }).toList();
      }
    } catch (_) {}
    return [];
  }
}

class BikeRouteOption {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  const BikeRouteOption({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}
