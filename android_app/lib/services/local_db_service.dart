import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDbService {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'lingodiary.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createV1Tables(db);
        await _createV2Tables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createV2Tables(db);
        }
      },
    );
  }

  static Future<void> _createV1Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS diary_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        saved_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lessons_cache (
        base TEXT PRIMARY KEY,
        display TEXT NOT NULL,
        variants_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> _createV2Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS home_cache (
        id INTEGER PRIMARY KEY,
        data_json TEXT NOT NULL,
        fetched_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS srs_scores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        entry_index INTEGER NOT NULL,
        score INTEGER NOT NULL,
        scored_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // ---- Diary ----

  static Future<void> saveDiaryContent(String content) async {
    final database = await db;
    await database.insert('diary_cache', {
      'content': content,
      'saved_at': DateTime.now().toIso8601String(),
      'synced': 0,
    });
  }

  static Future<String?> getLatestDiaryContent() async {
    final database = await db;
    final rows = await database.query(
      'diary_cache',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['content'] as String?;
  }

  static Future<void> markDiarySynced(int id) async {
    final database = await db;
    await database.update('diary_cache', {'synced': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  // ---- Lessons ----

  static Future<void> saveLessons(List<Map<String, dynamic>> lessons) async {
    final database = await db;
    final batch = database.batch();
    for (final lesson in lessons) {
      batch.insert(
        'lessons_cache',
        {
          'base': lesson['base'],
          'display': lesson['display'],
          'variants_json': jsonEncode(lesson['variants']),
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  static Future<List<Map<String, dynamic>>> getLessons() async {
    final database = await db;
    return database.query('lessons_cache', orderBy: 'display DESC');
  }

  // ---- Home cache ----

  static Future<void> saveHomeData(Map<String, dynamic> data) async {
    final database = await db;
    await database.insert(
      'home_cache',
      {
        'id': 1,
        'data_json': jsonEncode(data),
        'fetched_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, dynamic>?> getCachedHomeData() async {
    final database = await db;
    final rows = await database.query('home_cache', where: 'id = 1');
    if (rows.isEmpty) return null;
    try {
      return jsonDecode(rows.first['data_json'] as String) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ---- SRS scores ----

  static Future<int> saveSrsScore({
    required String date,
    required int entryIndex,
    required int score,
    bool synced = false,
  }) async {
    final database = await db;
    return database.insert('srs_scores', {
      'date': date,
      'entry_index': entryIndex,
      'score': score,
      'scored_at': DateTime.now().toIso8601String(),
      'synced': synced ? 1 : 0,
    });
  }

  static Future<List<Map<String, dynamic>>> getUnsyncedScores() async {
    final database = await db;
    return database.query('srs_scores', where: 'synced = 0');
  }

  static Future<void> markScoreSynced(int id) async {
    final database = await db;
    await database.update('srs_scores', {'synced': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Returns review statistics for the stats/streak screen.
  static Future<Map<String, dynamic>> getReviewStats() async {
    final database = await db;

    // Total reviews
    final totalResult =
        await database.rawQuery('SELECT COUNT(*) as c FROM srs_scores');
    final total = (totalResult.first['c'] as int?) ?? 0;

    // Today's reviews (using local time)
    final todayResult = await database.rawQuery(
      "SELECT COUNT(*) as c FROM srs_scores "
      "WHERE date(scored_at, 'localtime') = date('now', 'localtime')",
    );
    final todayCount = (todayResult.first['c'] as int?) ?? 0;

    // Score distribution
    final distResult = await database.rawQuery(
      'SELECT score, COUNT(*) as c FROM srs_scores GROUP BY score ORDER BY score',
    );
    final distribution = <int, int>{};
    for (final row in distResult) {
      distribution[(row['score'] as int?) ?? 0] = (row['c'] as int?) ?? 0;
    }

    // Streak: fetch all distinct review days, ordered descending
    final daysResult = await database.rawQuery(
      "SELECT DISTINCT date(scored_at, 'localtime') as d "
      'FROM srs_scores ORDER BY d DESC',
    );
    final days = daysResult.map((r) => r['d'] as String).toList();

    int streak = 0;
    if (days.isNotEmpty) {
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final yesterdayDt = today.subtract(const Duration(days: 1));
      final yesterdayStr =
          '${yesterdayDt.year}-${yesterdayDt.month.toString().padLeft(2, '0')}-${yesterdayDt.day.toString().padLeft(2, '0')}';

      // Streak starts only if reviewed today or yesterday
      if (days.first == todayStr || days.first == yesterdayStr) {
        DateTime cursor = days.first == todayStr ? today : yesterdayDt;
        for (final d in days) {
          final curStr =
              '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}-${cursor.day.toString().padLeft(2, '0')}';
          if (d == curStr) {
            streak++;
            cursor = cursor.subtract(const Duration(days: 1));
          } else {
            break;
          }
        }
      }
    }

    return {
      'total': total,
      'today': todayCount,
      'streak': streak,
      'distribution': distribution,
    };
  }

  /// Deletes all rows from all cache tables.
  static Future<void> clearAll() async {
    final database = await db;
    await database.delete('diary_cache');
    await database.delete('lessons_cache');
    await database.delete('home_cache');
    await database.delete('srs_scores');
  }
}
