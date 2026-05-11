import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Web implementation of LocalDbService.
// Web is always-online so there is no need for a persistent local DB.
// Lessons and home data are cached in SharedPreferences (survives page reload).
// Diary entries and SRS scores are in-memory only (written to server directly).
class LocalDbService {
  static Map<String, dynamic>? _homeCache;
  static final List<Map<String, dynamic>> _pendingScores = [];
  static int _scoreIdCounter = 0;

  // ---- Diary (no local cache on web) ----

  static Future<void> saveDiaryContent(String content) async {}

  static Future<String?> getLatestDiaryContent() async => null;

  static Future<void> markDiarySynced(int id) async {}

  static Future<List<Map<String, dynamic>>> getUnsyncedDiaryEntries() async => [];

  // ---- Lessons (cached in SharedPreferences) ----

  static Future<void> saveLessons(List<Map<String, dynamic>> lessons) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('web_lessons_cache', jsonEncode(lessons));
  }

  static Future<List<Map<String, dynamic>>> getLessons() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('web_lessons_cache');
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // ---- Home cache (in-memory) ----

  static Future<void> saveHomeData(Map<String, dynamic> data) async {
    _homeCache = data;
  }

  static Future<Map<String, dynamic>?> getCachedHomeData() async => _homeCache;

  // ---- SRS scores (in-memory, synced immediately on web) ----

  static Future<int> saveSrsScore({
    required String date,
    required int entryIndex,
    required int score,
    bool synced = false,
  }) async {
    final id = ++_scoreIdCounter;
    if (!synced) {
      _pendingScores.add({
        'id': id,
        'date': date,
        'entry_index': entryIndex,
        'score': score,
        'scored_at': DateTime.now().toIso8601String(),
        'synced': 0,
      });
    }
    return id;
  }

  static Future<List<Map<String, dynamic>>> getUnsyncedScores() async =>
      List.of(_pendingScores);

  static Future<void> markScoreSynced(int id) async {
    _pendingScores.removeWhere((s) => s['id'] == id);
  }

  static Future<Map<String, dynamic>> getReviewStats() async => {
        'total': 0,
        'today': 0,
        'streak': 0,
        'distribution': <int, int>{},
      };

  static Future<void> clearAll() async {
    _homeCache = null;
    _pendingScores.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('web_lessons_cache');
  }
}
