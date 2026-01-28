import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'local_cache_service.dart';

class NavigationService {
  final LocalCacheService _cacheService = LocalCacheService.instance;

  // 1. Search for Places (Nominatim API) - with caching
  Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    if (query.length < 3) return []; // Don't search for "a" or "ab"

    // Check cache first
    final cached = await _cacheService.getCachedPlaceSearch(query);
    if (cached != null) {
      debugPrint('[NAV] Using cached place search for: $query');
      return cached;
    }

    // If offline, return empty
    if (!_cacheService.isOnline) {
      debugPrint('[NAV] Offline - cannot search places');
      return [];
    }

    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5',
    );

    try {
      final response = await http.get(
        url,
        headers: {'User-Agent': 'BestBikePaths_StudentProject'},
      );

      if (response.statusCode == 200) {
        final results = List<Map<String, dynamic>>.from(
          json.decode(response.body),
        );

        // Cache the results
        if (results.isNotEmpty) {
          await _cacheService.cachePlaceSearch(query, results);
        }

        return results;
      }
    } catch (e) {
      debugPrint('[NAV] Place search error: $e');
    }
    return [];
  }

  // 2. Reverse Geocoding - Get address from coordinates (Nominatim API)
  Future<String?> reverseGeocode(double latitude, double longitude) async {
    // If offline, return a simple coordinate string
    if (!_cacheService.isOnline) {
      return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
    }

    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?lat=$latitude&lon=$longitude&format=json&addressdetails=1',
    );

    try {
      final response = await http.get(
        url,
        headers: {'User-Agent': 'BestBikePaths_StudentProject'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['display_name'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // 3. Get Bike Routes (OSRM API) - with offline support
  Future<List<BikeRouteOption>> getBikeRoutes(
    LatLng start,
    LatLng end, {
    int maxRoutes = 5,
    bool cacheResult = true,
  }) async {
    // Check cache first
    final cachedRoute = await _cacheService.getCachedRoute(start, end);
    if (cachedRoute != null) {
      debugPrint('[NAV] Using cached route');
      return [
        BikeRouteOption(
          points: cachedRoute.points,
          distanceMeters: cachedRoute.distanceMeters,
          durationSeconds: cachedRoute.durationSeconds,
          isFromCache: true,
        ),
      ];
    }

    // If offline and no cache, try to create a simple direct route
    if (!_cacheService.isOnline) {
      debugPrint('[NAV] Offline - creating direct route');
      return [_createDirectRoute(start, end)];
    }

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

        final bikeRoutes = routes.take(maxRoutes).map((route) {
          final geometry = route['geometry']['coordinates'] as List;
          final points = geometry
              .map((coord) => LatLng(coord[1].toDouble(), coord[0].toDouble()))
              .toList();

          final distanceMeters = (route['distance'] as num).toDouble();
          var durationSeconds = (route['duration'] as num).toDouble();

          // Sanity check: OSRM may return unrealistic times
          final avgSpeedKmh =
              (distanceMeters / 1000) / (durationSeconds / 3600);
          if (avgSpeedKmh > 20 || durationSeconds <= 0) {
            durationSeconds = (distanceMeters / 1000) / 15 * 3600;
          }

          return BikeRouteOption(
            points: points,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds,
          );
        }).toList();

        // Cache the first (best) route
        if (cacheResult && bikeRoutes.isNotEmpty) {
          final best = bikeRoutes.first;
          await _cacheService.cacheRoute(
            start: start,
            end: end,
            routePoints: best.points,
            distanceMeters: best.distanceMeters,
            durationSeconds: best.durationSeconds,
          );
        }

        return bikeRoutes;
      }
    } catch (e) {
      debugPrint('[NAV] Route fetch error: $e');
    }

    // Fallback to direct route if online request failed
    return [_createDirectRoute(start, end)];
  }

  /// Create a simple direct route when offline or API fails
  BikeRouteOption _createDirectRoute(LatLng start, LatLng end) {
    const distance = Distance();
    final meters = distance.as(LengthUnit.Meter, start, end);

    // Create intermediate points for smoother display
    final points = <LatLng>[start];
    const numPoints = 10;
    for (int i = 1; i < numPoints; i++) {
      final fraction = i / numPoints;
      final lat = start.latitude + (end.latitude - start.latitude) * fraction;
      final lon =
          start.longitude + (end.longitude - start.longitude) * fraction;
      points.add(LatLng(lat, lon));
    }
    points.add(end);

    // Estimate duration at 12 km/h (slower for direct/unknown route)
    final durationSeconds = (meters / 1000) / 12 * 3600;

    return BikeRouteOption(
      points: points,
      distanceMeters: meters,
      durationSeconds: durationSeconds,
      isFromCache: false,
      isDirectRoute: true,
    );
  }

  /// Pre-cache routes for common destinations
  Future<void> preCacheRoutes(
    LatLng currentLocation,
    List<LatLng> destinations,
  ) async {
    if (!_cacheService.isOnline) return;

    for (final dest in destinations) {
      final existing = await _cacheService.getCachedRoute(
        currentLocation,
        dest,
      );
      if (existing == null) {
        await getBikeRoutes(
          currentLocation,
          dest,
          maxRoutes: 1,
          cacheResult: true,
        );
        // Small delay to avoid rate limiting
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }
}

class BikeRouteOption {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final bool isFromCache;
  final bool isDirectRoute;

  const BikeRouteOption({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.isFromCache = false,
    this.isDirectRoute = false,
  });

  /// Get formatted distance string
  String get distanceText {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.toInt()} m';
  }

  /// Get formatted duration string
  String get durationText {
    final minutes = (durationSeconds / 60).round();
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '${hours}h ${mins}m';
    }
    return '$minutes min';
  }
}
