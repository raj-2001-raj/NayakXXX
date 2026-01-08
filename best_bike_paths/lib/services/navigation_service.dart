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

    final response = await http.get(
      url,
      headers: {'User-Agent': 'BestBikePaths_StudentProject'},
    );

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(json.decode(response.body));
    }
    return [];
  }

  // 2. Get Bike Routes (OSRM API)
  Future<List<LatLng>> getBikeRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
      'http://router.project-osrm.org/route/v1/bicycle/'
      '${start.longitude},${start.latitude};'
      '${end.longitude},${end.latitude}'
      '?overview=full&geometries=geojson',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final geometry = data['routes'][0]['geometry']['coordinates'] as List;

      return geometry
          .map((coord) => LatLng(coord[1].toDouble(), coord[0].toDouble()))
          .toList();
    }
    return [];
  }
}
