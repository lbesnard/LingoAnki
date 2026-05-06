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
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE diary_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL,
            saved_at TEXT NOT NULL,
            synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE lessons_cache (
            base TEXT PRIMARY KEY,
            display TEXT NOT NULL,
            variants_json TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
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

  /// Deletes all rows from all cache tables.
  static Future<void> clearAll() async {
    final database = await db;
    await database.delete('diary_cache');
    await database.delete('lessons_cache');
  }
}
