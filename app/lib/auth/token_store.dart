import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the session token between app launches.
///
/// Backed by the platform keystore — Keychain on Apple platforms,
/// EncryptedSharedPreferences (Android Keystore) on Android — so the token is
/// not sitting in a readable file. A token is a bearer credential: anyone
/// holding it is logged in as the user until it expires.
class TokenStore {
  // v11 defaults are already the strong ones — AES-GCM data encryption with
  // RSA-OAEP key wrapping in the Android Keystore, Keychain on Apple platforms
  // — so no options need overriding here.
  const TokenStore({this.storage = const FlutterSecureStorage()});

  static const _tokenKey = 'diarias.session_token';

  final FlutterSecureStorage storage;

  Future<String?> read() async {
    try {
      final token = await storage.read(key: _tokenKey);
      // Treat an empty string as absent so a botched write cannot leave the app
      // trying to authenticate with "".
      return (token == null || token.isEmpty) ? null : token;
    } catch (e) {
      // A locked or unavailable keystore must not stop the app from opening —
      // it just means the user has to log in again.
      debugPrint('TokenStore.read failed: $e');
      return null;
    }
  }

  Future<void> write(String token) async {
    try {
      await storage.write(key: _tokenKey, value: token);
    } catch (e) {
      // The session still works for this run; only persistence is lost.
      debugPrint('TokenStore.write failed: $e');
    }
  }

  Future<void> clear() async {
    try {
      await storage.delete(key: _tokenKey);
    } catch (e) {
      debugPrint('TokenStore.clear failed: $e');
    }
  }
}
