import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:latlong2/latlong.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sync status for UI display
enum SyncStatus { idle, syncing, success, error, offline }

/// Result of a sync operation
class SyncResult {
  final int syncedReports;
  final int failedReports;
  final int cachedRoutes;
  final String? errorMessage;

  const SyncResult({
    this.syncedReports = 0,
    this.failedReports = 0,
    this.cachedRoutes = 0,
    this.errorMessage,
  });

  bool get hasErrors => failedReports > 0 || errorMessage != null;
  bool get isEmpty => syncedReports == 0 && cachedRoutes == 0;
}

/// Local cache service for offline support with automatic sync
class LocalCacheService {
  static LocalCacheService? _instance;
  static Database? _database;

  // Connectivity monitoring
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  final _pendingCountController = StreamController<int>.broadcast();

  // Callbacks
  Function(SyncResult)? onSyncComplete;

  LocalCacheService._();

  /// Singleton instance
  static LocalCacheService get instance {
    _instance ??= LocalCacheService._();
    return _instance!;
  }

  /// Stream of sync status updates
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;

  /// Stream of pending report count
  Stream<int> get pendingCountStream => _pendingCountController.stream;

  /// Current online status
  bool get isOnline => _isOnline;

  /// Initialize the service and start monitoring connectivity
  Future<void> initialize() async {
    await database; // Ensure DB is ready

    // Check initial connectivity
    final result = await Connectivity().checkConnectivity();
    _isOnline = !result.contains(ConnectivityResult.none);

    // Start listening to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _handleConnectivityChange,
    );

    // Update pending count
    _updatePendingCount();

    // If online, try to sync any pending data
    if (_isOnline) {
      syncPendingData();
    }

    debugPrint('[CACHE] LocalCacheService initialized. Online: $_isOnline');
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final wasOffline = !_isOnline;
    _isOnline = !results.contains(ConnectivityResult.none);

    debugPrint('[CACHE] Connectivity changed. Online: $_isOnline');

    if (_isOnline) {
      _syncStatusController.add(SyncStatus.idle);

      // Just came online - sync pending data
      if (wasOffline) {
        debugPrint('[CACHE] Back online - starting sync...');
        syncPendingData();
      }
    } else {
      _syncStatusController.add(SyncStatus.offline);
    }
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'bbp_cache.db');

    return openDatabase(
      path,
      version: 2, // Bumped version for new tables
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add new tables for v2
          await db.execute('''
            CREATE TABLE IF NOT EXISTS cached_routes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              start_lat REAL NOT NULL,
              start_lon REAL NOT NULL,
              end_lat REAL NOT NULL,
              end_lon REAL NOT NULL,
              route_json TEXT NOT NULL,
              distance_meters REAL,
              duration_seconds REAL,
              cached_at TEXT NOT NULL,
              expires_at TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS cached_places (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              query TEXT NOT NULL,
              results_json TEXT NOT NULL,
              cached_at TEXT NOT NULL,
              expires_at TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS sync_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              action TEXT NOT NULL,
              item_count INTEGER,
              success INTEGER,
              error_message TEXT,
              synced_at TEXT NOT NULL
            )
          ''');
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    // Cache for anomalies (for offline display and route planning)
    await db.execute('''
      CREATE TABLE cached_anomalies (
        id TEXT PRIMARY KEY,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        severity REAL,
        category TEXT,
        verified INTEGER DEFAULT 0,
        trust_level TEXT,
        cached_at TEXT NOT NULL
      )
    ''');

    // Cache for pending reports (when offline)
    await db.execute('''
      CREATE TABLE pending_reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        category TEXT NOT NULL,
        is_manual INTEGER NOT NULL,
        ride_id TEXT,
        created_at TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        last_error TEXT
      )
    ''');

    // Cache for routes (offline route planning)
    await db.execute('''
      CREATE TABLE cached_routes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        start_lat REAL NOT NULL,
        start_lon REAL NOT NULL,
        end_lat REAL NOT NULL,
        end_lon REAL NOT NULL,
        route_json TEXT NOT NULL,
        distance_meters REAL,
        duration_seconds REAL,
        cached_at TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )
    ''');

    // Create index for fast route lookup
    await db.execute('''
      CREATE INDEX idx_routes_coords ON cached_routes(start_lat, start_lon, end_lat, end_lon)
    ''');

    // Cache for place search results
    await db.execute('''
      CREATE TABLE cached_places (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        query TEXT NOT NULL,
        results_json TEXT NOT NULL,
        cached_at TEXT NOT NULL,
        expires_at TEXT NOT NULL
      )
    ''');

    // Create index for fast place lookup
    await db.execute('''
      CREATE INDEX idx_places_query ON cached_places(query)
    ''');

    // Sync log for debugging
    await db.execute('''
      CREATE TABLE sync_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        item_count INTEGER,
        success INTEGER,
        error_message TEXT,
        synced_at TEXT NOT NULL
      )
    ''');
  }

  // ========== PENDING REPORTS (OFFLINE ANOMALY REPORTING) ==========

  /// Save a pending report when offline
  Future<int> savePendingReport({
    required LatLng location,
    required String category,
    required bool isManual,
    String? rideId,
  }) async {
    final db = await database;
    final id = await db.insert('pending_reports', {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'category': category,
      'is_manual': isManual ? 1 : 0,
      'ride_id': rideId,
      'created_at': DateTime.now().toIso8601String(),
      'retry_count': 0,
    });

    debugPrint(
      '[CACHE] Saved pending report #$id: $category at ${location.latitude}, ${location.longitude}',
    );
    _updatePendingCount();

    // Try to sync immediately if online
    if (_isOnline) {
      syncPendingData();
    }

    return id;
  }

  /// Get all pending reports to sync
  Future<List<Map<String, dynamic>>> getPendingReports() async {
    final db = await database;
    return db.query('pending_reports', orderBy: 'created_at ASC');
  }

  /// Get count of pending reports
  Future<int> getPendingReportCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM pending_reports',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Delete synced report
  Future<void> deletePendingReport(int id) async {
    final db = await database;
    await db.delete('pending_reports', where: 'id = ?', whereArgs: [id]);
    _updatePendingCount();
  }

  /// Update retry count and error for a failed report
  Future<void> markReportFailed(int id, String error) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE pending_reports SET retry_count = retry_count + 1, last_error = ? WHERE id = ?',
      [error, id],
    );
  }

  void _updatePendingCount() async {
    final count = await getPendingReportCount();
    _pendingCountController.add(count);
  }

  // ========== SYNC MECHANISM ==========

  /// Sync all pending data to server
  Future<SyncResult> syncPendingData() async {
    if (!_isOnline) {
      debugPrint('[CACHE] Cannot sync - offline');
      return const SyncResult(errorMessage: 'Device is offline');
    }

    _syncStatusController.add(SyncStatus.syncing);
    debugPrint('[CACHE] Starting sync...');

    int syncedCount = 0;
    int failedCount = 0;
    String? lastError;

    try {
      final pendingReports = await getPendingReports();
      debugPrint('[CACHE] Found ${pendingReports.length} pending reports');

      for (final report in pendingReports) {
        try {
          // Skip reports that have failed too many times
          final retryCount = report['retry_count'] as int? ?? 0;
          if (retryCount >= 5) {
            debugPrint(
              '[CACHE] Skipping report ${report['id']} - too many retries',
            );
            continue;
          }

          final success = await _syncReportToServer(report);
          if (success) {
            await deletePendingReport(report['id'] as int);
            syncedCount++;
            debugPrint('[CACHE] Synced report ${report['id']}');
          } else {
            await markReportFailed(report['id'] as int, 'Sync failed');
            failedCount++;
          }
        } catch (e) {
          debugPrint('[CACHE] Failed to sync report ${report['id']}: $e');
          await markReportFailed(report['id'] as int, e.toString());
          failedCount++;
          lastError = e.toString();
        }
      }

      // Log the sync
      await _logSync('sync_reports', syncedCount, failedCount == 0, lastError);

      // Also refresh anomaly cache while we're online
      await refreshAnomalyCache();
    } catch (e) {
      debugPrint('[CACHE] Sync error: $e');
      lastError = e.toString();
      _syncStatusController.add(SyncStatus.error);
    }

    final result = SyncResult(
      syncedReports: syncedCount,
      failedReports: failedCount,
      errorMessage: lastError,
    );

    _syncStatusController.add(
      result.hasErrors ? SyncStatus.error : SyncStatus.success,
    );

    // Reset to idle after a delay
    Future.delayed(const Duration(seconds: 3), () {
      if (_isOnline) {
        _syncStatusController.add(SyncStatus.idle);
      }
    });

    onSyncComplete?.call(result);
    debugPrint(
      '[CACHE] Sync complete: $syncedCount synced, $failedCount failed',
    );

    return result;
  }

  /// Sync a single report to the server
  Future<bool> _syncReportToServer(Map<String, dynamic> report) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      debugPrint('[CACHE] Cannot sync - not authenticated');
      return false;
    }

    try {
      // Format location as PostGIS point
      final lat = report['latitude'] as double;
      final lon = report['longitude'] as double;
      final pointWkt = 'SRID=4326;POINT($lon $lat)';

      await client.from('anomalies').insert({
        'user_id': user.id,
        'location': pointWkt,
        'category': report['category'],
        'severity': (report['is_manual'] as int) == 1 ? 3 : 2,
        'ride_id': report['ride_id'],
        'created_at': report['created_at'],
        'synced_from_offline': true, // Mark as synced from offline
      });

      return true;
    } catch (e) {
      debugPrint('[CACHE] Failed to sync report to server: $e');
      return false;
    }
  }

  Future<void> _logSync(
    String action,
    int count,
    bool success,
    String? error,
  ) async {
    final db = await database;
    await db.insert('sync_log', {
      'action': action,
      'item_count': count,
      'success': success ? 1 : 0,
      'error_message': error,
      'synced_at': DateTime.now().toIso8601String(),
    });
  }

  // ========== ANOMALY CACHE (FOR OFFLINE ROUTE PLANNING) ==========

  /// Refresh the local anomaly cache from server
  Future<void> refreshAnomalyCache() async {
    if (!_isOnline) return;

    try {
      final client = Supabase.instance.client;
      final anomalies =
          await client
                  .from('anomalies')
                  .select('id,location,severity,category,verified,trust_level')
                  .gte(
                    'created_at',
                    DateTime.now()
                        .subtract(const Duration(days: 90))
                        .toIso8601String(),
                  )
              as List<dynamic>;

      await cacheAnomalies(anomalies.cast<Map<String, dynamic>>());
      debugPrint('[CACHE] Cached ${anomalies.length} anomalies');
    } catch (e) {
      debugPrint('[CACHE] Failed to refresh anomaly cache: $e');
    }
  }

  /// Cache anomalies for offline route planning
  Future<void> cacheAnomalies(List<Map<String, dynamic>> anomalies) async {
    final db = await database;
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();

    // Clear old cache first
    batch.delete('cached_anomalies');

    for (final anomaly in anomalies) {
      // Parse location from PostGIS format
      double? lat, lon;
      final locStr = anomaly['location']?.toString() ?? '';
      final match = RegExp(
        r'POINT\(([-\d.]+)\s+([-\d.]+)\)',
      ).firstMatch(locStr);
      if (match != null) {
        lon = double.tryParse(match.group(1)!);
        lat = double.tryParse(match.group(2)!);
      }

      if (lat != null && lon != null) {
        batch.insert('cached_anomalies', {
          'id': anomaly['id']?.toString() ?? '',
          'latitude': lat,
          'longitude': lon,
          'severity': (anomaly['severity'] as num?)?.toDouble() ?? 2.0,
          'category': anomaly['category']?.toString() ?? 'Unknown',
          'verified': anomaly['verified'] == true ? 1 : 0,
          'trust_level': anomaly['trust_level']?.toString(),
          'cached_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    await batch.commit(noResult: true);
  }

  /// Get cached anomalies for offline use
  Future<List<Map<String, dynamic>>> getCachedAnomalies() async {
    final db = await database;
    return db.query('cached_anomalies');
  }

  /// Get anomalies near a location (for offline route planning)
  Future<List<Map<String, dynamic>>> getAnomaliesNear(
    LatLng center,
    double radiusKm,
  ) async {
    final db = await database;

    // Simple bounding box query (not perfect circle, but fast)
    final latDelta = radiusKm / 111.0; // ~111km per degree latitude
    final lonDelta = radiusKm / (111.0 * cos(center.latitude * pi / 180));

    return db.query(
      'cached_anomalies',
      where: 'latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?',
      whereArgs: [
        center.latitude - latDelta,
        center.latitude + latDelta,
        center.longitude - lonDelta,
        center.longitude + lonDelta,
      ],
    );
  }

  // ========== ROUTE CACHE (OFFLINE ROUTE PLANNING) ==========

  /// Cache a route for offline use
  Future<void> cacheRoute({
    required LatLng start,
    required LatLng end,
    required List<LatLng> routePoints,
    required double distanceMeters,
    required double durationSeconds,
    Duration validFor = const Duration(days: 7),
  }) async {
    final db = await database;
    final now = DateTime.now();

    // Encode route points as JSON
    final routeJson = jsonEncode(
      routePoints.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList(),
    );

    await db.insert('cached_routes', {
      'start_lat': start.latitude,
      'start_lon': start.longitude,
      'end_lat': end.latitude,
      'end_lon': end.longitude,
      'route_json': routeJson,
      'distance_meters': distanceMeters,
      'duration_seconds': durationSeconds,
      'cached_at': now.toIso8601String(),
      'expires_at': now.add(validFor).toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    debugPrint(
      '[CACHE] Cached route from (${start.latitude}, ${start.longitude}) to (${end.latitude}, ${end.longitude})',
    );
  }

  /// Get a cached route if available
  Future<CachedRoute?> getCachedRoute(LatLng start, LatLng end) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Allow some tolerance for start/end coordinates (~100m)
    const tolerance = 0.001; // ~111 meters

    final results = await db.query(
      'cached_routes',
      where: '''
        start_lat BETWEEN ? AND ? AND
        start_lon BETWEEN ? AND ? AND
        end_lat BETWEEN ? AND ? AND
        end_lon BETWEEN ? AND ? AND
        expires_at > ?
      ''',
      whereArgs: [
        start.latitude - tolerance,
        start.latitude + tolerance,
        start.longitude - tolerance,
        start.longitude + tolerance,
        end.latitude - tolerance,
        end.latitude + tolerance,
        end.longitude - tolerance,
        end.longitude + tolerance,
        now,
      ],
      orderBy: 'cached_at DESC',
      limit: 1,
    );

    if (results.isEmpty) return null;

    final row = results.first;
    final routeJson = jsonDecode(row['route_json'] as String) as List;
    final points = routeJson
        .map((p) => LatLng(p['lat'] as double, p['lon'] as double))
        .toList();

    debugPrint('[CACHE] Found cached route with ${points.length} points');

    return CachedRoute(
      points: points,
      distanceMeters: (row['distance_meters'] as num).toDouble(),
      durationSeconds: (row['duration_seconds'] as num).toDouble(),
      cachedAt: DateTime.parse(row['cached_at'] as String),
    );
  }

  /// Get all cached routes (for display/management)
  Future<List<Map<String, dynamic>>> getAllCachedRoutes() async {
    final db = await database;
    return db.query('cached_routes', orderBy: 'cached_at DESC');
  }

  /// Delete expired routes
  Future<int> cleanExpiredRoutes() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return db.delete(
      'cached_routes',
      where: 'expires_at < ?',
      whereArgs: [now],
    );
  }

  // ========== PLACE SEARCH CACHE ==========

  /// Cache place search results
  Future<void> cachePlaceSearch(
    String query,
    List<Map<String, dynamic>> results,
  ) async {
    final db = await database;
    final now = DateTime.now();

    await db.insert('cached_places', {
      'query': query.toLowerCase(),
      'results_json': jsonEncode(results),
      'cached_at': now.toIso8601String(),
      'expires_at': now.add(const Duration(days: 30)).toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get cached place search results
  Future<List<Map<String, dynamic>>?> getCachedPlaceSearch(String query) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final results = await db.query(
      'cached_places',
      where: 'query = ? AND expires_at > ?',
      whereArgs: [query.toLowerCase(), now],
      limit: 1,
    );

    if (results.isEmpty) return null;

    final json = jsonDecode(results.first['results_json'] as String) as List;
    return json.cast<Map<String, dynamic>>();
  }

  // ========== CLEANUP ==========

  /// Clean up old data
  Future<void> cleanup() async {
    final deleted = await cleanExpiredRoutes();
    debugPrint('[CACHE] Cleaned up $deleted expired routes');

    // Also clean old sync logs (keep last 100)
    final db = await database;
    await db.rawDelete('''
      DELETE FROM sync_log WHERE id NOT IN (
        SELECT id FROM sync_log ORDER BY synced_at DESC LIMIT 100
      )
    ''');
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription?.cancel();
    _syncStatusController.close();
    _pendingCountController.close();
  }
}

/// Represents a cached route
class CachedRoute {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final DateTime cachedAt;

  const CachedRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.cachedAt,
  });

  bool get isFromCache => true;
}

// Math helper
double cos(double radians) => radians.cos();
double get pi => 3.14159265359;

extension _MathExtension on double {
  double cos() {
    double x = this;
    // Normalize to [0, 2π]
    while (x < 0) x += 2 * pi;
    while (x > 2 * pi) x -= 2 * pi;

    // Taylor series approximation
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 10; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }
}
