import 'dart:convert';
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

  static Future<String> _baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('server_url') ?? '';
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

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

  static Future<String> getDiary() async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final resp = await http.get(Uri.parse('$base/api/diary'), headers: headers).timeout(_timeout);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to get diary');
    return (jsonDecode(resp.body) as Map<String, dynamic>)['content'] as String? ?? '';
  }

  static Future<void> saveDiary(String content) async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final resp = await http
        .post(
          Uri.parse('$base/api/diary'),
          headers: headers,
          body: jsonEncode({'content': content}),
        )
        .timeout(_timeout);
    if (resp.statusCode != 200) throw ApiException(resp.statusCode, 'Failed to save diary');
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

  static Future<String> getDiaryEntryByDate(String date) async {
    final base = await _baseUrl();
    final headers = await _authHeaders();
    final resp = await http
        .get(Uri.parse('$base/api/diary/date/$date'), headers: headers)
        .timeout(_timeout);
    if (resp.statusCode != 200) {
      throw ApiException(resp.statusCode, 'Failed to get diary entry for $date');
    }
    return (jsonDecode(resp.body) as Map<String, dynamic>)['content'] as String? ?? '';
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
}
