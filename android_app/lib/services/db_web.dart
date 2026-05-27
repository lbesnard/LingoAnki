import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
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

  // ---- Home cache (SharedPreferences on web, survives page reload) ----

  static Future<void> saveHomeData(Map<String, dynamic> data) async {
    _homeCache = data;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('web_home_cache', jsonEncode(data));
  }

  static Future<Map<String, dynamic>?> getCachedHomeData() async {
    // First check in-memory cache (fastest)
    if (_homeCache != null) {
      debugPrint('[DEBUG] LocalDbService.getCachedHomeData: returning in-memory cache');
      return _homeCache;
    }

    // Fall back to SharedPreferences (survives page reload)
    debugPrint('[DEBUG] LocalDbService.getCachedHomeData: checking SharedPreferences');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('web_home_cache');
    debugPrint('[DEBUG] LocalDbService.getCachedHomeData: raw=${raw == null ? 'null' : 'present (${raw.substring(0, 50)}...)'}');
    if (raw == null) {
      debugPrint('[DEBUG] LocalDbService.getCachedHomeData: no cached data found');
      return null;
    }
    try {
      _homeCache = jsonDecode(raw) as Map<String, dynamic>;
      debugPrint('[DEBUG] LocalDbService.getCachedHomeData: successfully loaded from SharedPreferences');
      return _homeCache;
    } catch (e) {
      debugPrint('[DEBUG] LocalDbService.getCachedHomeData: error decoding cache: $e');
      return null;
    }
  }

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

  static Future<void> resetScoreSynced(int id) async {}

  static Future<void> cleanupOldSyncedRows({int days = 90}) async {}

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
    await prefs.remove('web_home_cache');
  }

  // ---- Lesson last_reviewed tracking (no-op on web) ----

  static Future<void> saveLessonLastReviewed(String date, String timestamp) async {}

  static Future<List<Map<String, dynamic>>> getUnsyncedLessonReviews() async => [];

  static Future<void> markLessonReviewSynced(String date) async {}

  static Future<List<Map<String, dynamic>>> getRecentlyStudiedLessons({int limit = 10}) async => [];
}
