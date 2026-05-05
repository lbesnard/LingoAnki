import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'jwt_token';
  static const _serverUrlKey = 'server_url';
  static const _usernameKey = 'username';

  static Future<void> saveSession(String token, String serverUrl) async {
    await _storage.write(key: _tokenKey, value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverUrlKey, serverUrl);
  }

  static Future<void> saveUsername(String username) async {
    await _storage.write(key: _usernameKey, value: username);
  }

  static Future<String?> getUsername() async {
    return _storage.read(key: _usernameKey);
  }

  static Future<String?> getToken() async {
    return _storage.read(key: _tokenKey);
  }

  /// Clears JWT token (and username) but keeps server_url and cached data.
  static Future<void> clearSession() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _usernameKey);
  }
}
