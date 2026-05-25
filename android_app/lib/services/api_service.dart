import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  static const _timeout = Duration(seconds: 15);

  /// Returns the API base URL.
  /// On web the app is served from the same origin, so relative URLs are used.
  static Future<String> baseUrl() async {
    if (kIsWeb) return '';
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('server_url') ?? '';
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  // Keep a private alias so existing internal callers are unchanged.
  static Future<String> _baseUrl() => baseUrl();

  static Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> login(
      String serverUrl, String username, String password) async {
    final url = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    final resp = await http
        .post(
          Uri.parse('$url/api/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(_timeout);
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, body['error'] ?? 'Login failed');
    }
    return body;
  }

  static Future<void> triggerGenerate() async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final resp =
        await http.post(Uri.parse('$base/api/generate'), headers: headers).timeout(_timeout);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to trigger generation');
  }

  static Future<String> getGenerateStatus() async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final resp = await http
        .get(Uri.parse('$base/api/generate/status'), headers: headers)
        .timeout(_timeout);
    if (resp.statusCode != 200) return '';
    return (jsonDecode(resp.body) as Map<String, dynamic>)['log'] as String? ?? '';
  }

  static Future<List<Map<String, dynamic>>> getLessons() async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final resp =
        await http.get(Uri.parse('$base/api/lessons'), headers: headers).timeout(_timeout);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to get lessons');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['lessons'] as List);
  }

  static Future<List<Map<String, dynamic>>> getSyncManifest() async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final resp = await http
        .get(Uri.parse('$base/api/sync/manifest'), headers: headers)
        .timeout(_timeout);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to get manifest');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['manifest'] as List);
  }

  static Future<http.Response> downloadFile(String relPath) async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final encoded = Uri.encodeFull('$base/api/sync/file/$relPath');
    return http.get(Uri.parse(encoded), headers: headers).timeout(const Duration(minutes: 2));
  }

  static Future<List<Map<String, dynamic>>> getLessonManifest(String lessonBase) async {
    final serverBase = await _baseUrl();
    final headers = await _authHeaders();
    // Use pathSegments to properly percent-encode spaces and emoji in lessonBase
    final serverUri = Uri.parse(serverBase);
    final uri = Uri(
      scheme: serverUri.scheme,
      host: serverUri.host,
      port: serverUri.port,
      pathSegments: [...serverUri.pathSegments, 'api', 'sync', 'manifest', lessonBase],
    );
    final resp = await http.get(uri, headers: headers).timeout(_timeout);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to get lesson manifest');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['manifest'] as List);
  }

  static Future<void> addDiaryEntry(String date, List<String> sentences) async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final resp = await http
        .post(
          Uri.parse('$base/api/diary/entry'),
          headers: headers,
          body: jsonEncode({'date': date, 'sentences': sentences}),
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      throw ApiException(resp.statusCode, body['error'] ?? 'Failed to add diary entry');
    }
  }

  static Future<Map<String, String>> fetchTprsKeywords() async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final resp =
        await http.get(Uri.parse('$base/api/config'), headers: headers).timeout(_timeout);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to get config');
    final data = (jsonDecode(resp.body) as Map<String, dynamic>)['tprs'] as Map<String, dynamic>;
    return {
      'sentence': data['sentence'] as String? ?? 'SETNING:',
      'question': data['question'] as String? ?? 'SPØRSMÅL:',
      'answer': data['answer'] as String? ?? 'SVAR:',
    };
  }

  // ── Diary JSON / SRS endpoints ──────────────────────────────────────────────

  /// Fetch all lesson entries (with audio timings) for a date + variant.
  /// [date] in YYYY-MM-DD or YYYY/MM/DD format.
  static Future<Map<String, dynamic>> getLessonEntries(
      String date, String variant) async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    // Normalise to YYYY/MM/DD for the URL
    final dateFmt = date.replaceAll('/', '-');
    final resp = await http
        .get(
          Uri.parse('$base/api/lessons/entries/$dateFmt/$variant'),
          headers: headers,
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, 'Failed to get lesson entries');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Score an individual entry via SM-2.
  /// [score]: 0=Again, 2=Hard, 3=Good, 5=Easy
  static Future<Map<String, dynamic>> scoreEntry(
      String date, int entryIndex, int score) async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final resp = await http
        .post(
          Uri.parse('$base/api/lessons/score'),
          headers: headers,
          body: jsonEncode({
            'date': date,
            'entry_index': entryIndex,
            'score': score,
          }),
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, 'Failed to score entry');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Fetch home dashboard data: stats, recent lessons, recommendation.
  static Future<Map<String, dynamic>> getHomeData() async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final url = '$base/api/home';
    debugPrint('[DEBUG] getHomeData: base=$base, url=$url');
    debugPrint('[DEBUG] getHomeData: headers=$headers');
    try {
      final resp = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(_timeout);
      debugPrint('[DEBUG] getHomeData: statusCode=${resp.statusCode}');

      // Handle unauthorized - token might be expired
      if (resp.statusCode == 401) {
        debugPrint('[DEBUG] getHomeData: Received 401, clearing session');
        await AuthService.clearSession();
        throw ApiException(401, 'Session expired. Please log in again.');
      }

      if (resp.statusCode != 200) {
        debugPrint('[DEBUG] getHomeData: response body=${resp.body}');
        throw ApiException(resp.statusCode, 'Failed to get home data');
      }
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[DEBUG] getHomeData: exception=$e');
      rethrow;
    }
  }

  /// Fetch sentences due for review (Anki-style).
  static Future<List<Map<String, dynamic>>> getDueSentences({
    int limit = 20,
    String variant = 'original',
  }) async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final uri = Uri.parse('$base/api/sentences/due').replace(
      queryParameters: {'limit': '$limit', 'variant': variant},
    );
    final resp = await http.get(uri, headers: headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, 'Failed to get due sentences');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['sentences'] as List);
  }

  /// Trigger Q&A translation backfill (background job on server).
  static Future<void> triggerQaTranslationBackfill() async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    await http
        .post(Uri.parse('$base/api/backfill/qa_translations'), headers: headers)
        .timeout(_timeout);
  }

  /// Trigger audio timing backfill (background job on server).
  /// Regenerates per-sentence segment MP3s and writes timing data to diary.json.
  /// When [overwrite] is true, forces TTS re-generation for all days (slow).
  /// When false (default), only recomputes timing from existing segment files
  /// when zero timing is detected — much faster.
  static Future<void> triggerAudioTimingBackfill({bool overwrite = false}) async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    await http
        .post(
          Uri.parse('$base/api/backfill/audio_timing'),
          headers: headers,
          body: jsonEncode({'overwrite': overwrite}),
        )
        .timeout(_timeout);
  }

  /// Trigger full maintenance backfill (background job on server).
  /// Runs in sequence: sync diary.json → Q&A translations → audio timing.
  static Future<void> triggerBackfillAll() async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    await http
        .post(Uri.parse('$base/api/backfill/all'), headers: headers)
        .timeout(_timeout);
  }

  /// Get the last_reviewed timestamp for a specific lesson date
  static Future<Map<String, dynamic>> getLessonLastReviewed(String date) async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final dateFmt = date.replaceAll('/', '-');
    final resp = await http
        .get(
          Uri.parse('$base/api/lessons/last_reviewed/$dateFmt'),
          headers: headers,
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, 'Failed to get lesson last_reviewed');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Update the last_reviewed timestamp for a specific lesson date
  static Future<Map<String, dynamic>> updateLessonLastReviewed(String date, {String? timestamp}) async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final dateFmt = date.replaceAll('/', '-');
    final body = timestamp != null ? {'timestamp': timestamp} : {};

    final resp = await http
        .put(
          Uri.parse('$base/api/lessons/last_reviewed/$dateFmt'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, 'Failed to update lesson last_reviewed');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// Get recently studied lessons (by last_reviewed timestamp)
  static Future<List<Map<String, dynamic>>> getRecentlyStudiedLessons({int limit = 10}) async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final uri = Uri.parse('$base/api/lessons/recently_studied').replace(
      queryParameters: {'limit': '$limit'},
    );
    final resp = await http.get(uri, headers: headers).timeout(_timeout);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, 'Failed to get recently studied lessons');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['lessons'] as List);
  }
}
