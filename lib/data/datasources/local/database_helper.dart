import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/scan_history_model.dart';
import '../../models/user_profile_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('food_database.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 11,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 8) {
          try {
            await db.execute("ALTER TABLE user_profile ADD COLUMN allergies TEXT DEFAULT '[]'");
            await db.execute("ALTER TABLE user_profile ADD COLUMN is_obesity_mode INTEGER DEFAULT 0");
          } catch (_) {
            await db.execute('DROP TABLE IF EXISTS scan_history');
            await db.execute('DROP TABLE IF EXISTS user_profile');
            await _createDB(db, newVersion);
          }
        }
        if (oldVersion < 9) {
          try {
            await db.execute("ALTER TABLE scan_history ADD COLUMN original_image_base64 TEXT");
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE scan_history ADD COLUMN food_image_base64 TEXT");
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE scan_history ADD COLUMN label_image_base64 TEXT");
          } catch (_) {}
        }
        if (oldVersion < 10) {
          try {
            await db.execute("ALTER TABLE scan_history ADD COLUMN ai_suggestion TEXT");
          } catch (_) {}
        }
        if (oldVersion < 11) {
          try {
            await db.execute("ALTER TABLE scan_history ADD COLUMN serving_units REAL");
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE scan_history ADD COLUMN consumption_ratio REAL DEFAULT 1.0");
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE scan_history ADD COLUMN log_date TEXT");
          } catch (_) {}
        }
      },
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE scan_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      original_image TEXT NOT NULL,
      cropped_food_image TEXT NOT NULL,
      cropped_label_image TEXT,
      original_image_base64 TEXT,
      food_image_base64 TEXT,
      label_image_base64 TEXT,
      ai_suggestion TEXT,
      food_name TEXT NOT NULL,
      weight REAL,
      serving_units REAL,
      consumption_ratio REAL NOT NULL DEFAULT 1.0,
      log_date TEXT,
      nutrition_data TEXT NOT NULL,
      main_group TEXT NOT NULL,
      created_at TEXT NOT NULL,
      is_synced INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT
    )
    ''');

    await db.execute('''
    CREATE TABLE user_profile (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      dob TEXT NOT NULL,
      weight REAL NOT NULL,
      height REAL NOT NULL,
      gender TEXT NOT NULL,
      activity_factor REAL NOT NULL,
      goal TEXT NOT NULL,
      medical_conditions TEXT NOT NULL,
      medical_flags TEXT NOT NULL,
      allergies TEXT NOT NULL DEFAULT '[]',
      is_obesity_mode INTEGER NOT NULL DEFAULT 0,
      bmr REAL NOT NULL,
      tdee REAL NOT NULL,
      target_calories REAL NOT NULL,
      budget_protein REAL NOT NULL,
      budget_carb REAL NOT NULL,
      budget_fat REAL NOT NULL,
      budget_fiber REAL NOT NULL,
      ceiling_sugar REAL NOT NULL,
      ceiling_sodium REAL NOT NULL,
      ceiling_sat_fat REAL NOT NULL,
      ceiling_protein_kidney REAL NOT NULL,
      is_synced INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT
    )
    ''');
  }

  // --- SCAN HISTORY ---
  Future<int> insertScan(ScanHistory scan) async {
    final db = await instance.database;
    return await db.insert('scan_history', scan.toMap());
  }

  Future<int> updateScan(ScanHistory scan) async {
    final db = await instance.database;
    return await db.update(
      'scan_history',
      scan.toMap(),
      where: 'id = ?',
      whereArgs: [scan.id],
    );
  }

  Future<List<ScanHistory>> getAllScans() async {
    final db = await instance.database;
    final result = await db.query('scan_history', orderBy: 'created_at DESC');
    return result.map((map) => ScanHistory.fromMap(map)).toList();
  }

  Future<List<ScanHistory>> getDailyScans(String dateStr) async {
    final db = await instance.database;
    final result = await db.query(
      'scan_history',
      where: 'log_date = ? OR created_at LIKE ?',
      whereArgs: [dateStr, '$dateStr%'],
      orderBy: 'created_at DESC',
    );
    return result.map((map) => ScanHistory.fromMap(map)).toList();
  }

  Future<void> deleteScans(List<int> ids) async {
    final db = await instance.database;
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      'scan_history',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  // --- SYNC HELPERS ---
  Future<List<ScanHistory>> getUnsyncedScans() async {
    final db = await instance.database;
    final result = await db.query(
      'scan_history',
      where: 'is_synced = ?',
      whereArgs: [0],
    );
    return result.map((map) => ScanHistory.fromMap(map)).toList();
  }

  Future<void> markScansAsSynced(List<int> ids) async {
    final db = await instance.database;
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE scan_history SET is_synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  Future<void> markProfileAsSynced() async {
    final db = await instance.database;
    await db.rawUpdate('UPDATE user_profile SET is_synced = 1');
  }

  // --- USER PROFILE ---
  Future<UserProfile?> getUserProfile() async {
    final db = await instance.database;
    final result = await db.query('user_profile', limit: 1);
    if (result.isNotEmpty) {
      return UserProfile.fromMap(result.first);
    }
    return null;
  }

  Future<int> saveUserProfile(UserProfile profile) async {
    final db = await instance.database;
    await db.delete('user_profile');
    return await db.insert('user_profile', profile.toMap());
  }

  Future<bool> hasUnsyncedData() async {
    final db = await instance.database;
    final unsyncedScans = await db.query(
      'scan_history',
      where: 'is_synced = ?',
      whereArgs: [0],
      limit: 1,
    );
    if (unsyncedScans.isNotEmpty) return true;

    final unsyncedProfile = await db.query(
      'user_profile',
      where: 'is_synced = ?',
      whereArgs: [0],
      limit: 1,
    );
    return unsyncedProfile.isNotEmpty;
  }

  Future<void> clearAllLocalData() async {
    final db = await instance.database;
    await db.delete('scan_history');
    await db.delete('user_profile');
  }
}
