import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:latlong2/latlong.dart';

/// Local cache service for offline support
/// TODO: Implement full offline mode with sync when back online
class LocalCacheService {
  static Database? _database;

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
      version: 1,
      onCreate: (db, version) async {
        // Cache for anomalies
        await db.execute('''
          CREATE TABLE cached_anomalies (
            id TEXT PRIMARY KEY,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            severity TEXT,
            category TEXT,
            synced INTEGER DEFAULT 0,
            created_at TEXT
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
            created_at TEXT NOT NULL
          )
        ''');

        // Cache for route preferences
        await db.execute('''
          CREATE TABLE route_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_lat REAL,
            start_lon REAL,
            end_lat REAL,
            end_lon REAL,
            route_data TEXT,
            cached_at TEXT
          )
        ''');
      },
    );
  }

  /// Save a pending report when offline
  Future<void> savePendingReport({
    required LatLng location,
    required String category,
    required bool isManual,
    String? rideId,
  }) async {
    final db = await database;
    await db.insert('pending_reports', {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'category': category,
      'is_manual': isManual ? 1 : 0,
      'ride_id': rideId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Get all pending reports to sync
  Future<List<Map<String, dynamic>>> getPendingReports() async {
    final db = await database;
    return db.query('pending_reports');
  }

  /// Delete synced reports
  Future<void> deletePendingReport(int id) async {
    final db = await database;
    await db.delete('pending_reports', where: 'id = ?', whereArgs: [id]);
  }

  /// Cache anomalies for offline route planning
  Future<void> cacheAnomalies(List<Map<String, dynamic>> anomalies) async {
    final db = await database;
    final batch = db.batch();

    for (final anomaly in anomalies) {
      batch.insert(
        'cached_anomalies',
        anomaly,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Get cached anomalies
  Future<List<Map<String, dynamic>>> getCachedAnomalies() async {
    final db = await database;
    return db.query('cached_anomalies');
  }
}
