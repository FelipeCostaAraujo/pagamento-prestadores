import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

@immutable
class StoredSessionTokens {
  const StoredSessionTokens({this.accessToken, this.refreshToken});

  final String? accessToken;
  final String? refreshToken;

  bool get isEmpty => accessToken == null && refreshToken == null;
}

/// Persists the session token pair between app launches.
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

  // Keep the original key for access-token compatibility with installations
  // made before refresh tokens existed.
  static const _accessTokenKey = 'diarias.session_token';
  static const _refreshTokenKey = 'diarias.refresh_token';

  final FlutterSecureStorage storage;

  Future<StoredSessionTokens?> read() async {
    final accessToken = await _readKey(_accessTokenKey);
    final refreshToken = await _readKey(_refreshTokenKey);
    final tokens = StoredSessionTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    return tokens.isEmpty ? null : tokens;
  }

  Future<void> write({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _writeKey(_accessTokenKey, accessToken);
    await _writeKey(_refreshTokenKey, refreshToken);
  }

  Future<void> clear() async {
    await _writeKey(_accessTokenKey, null);
    await _writeKey(_refreshTokenKey, null);
  }

  Future<String?> _readKey(String key) async {
    try {
      final token = await storage.read(key: key);
      // Treat an empty string as absent so a botched write cannot leave the app
      // trying to authenticate with "".
      return (token == null || token.isEmpty) ? null : token;
    } catch (e) {
      // A locked or unavailable keystore must not stop the app from opening —
      // it just means the user has to log in again.
      debugPrint('TokenStore.read($key) failed: $e');
      return null;
    }
  }

  Future<void> _writeKey(String key, String? value) async {
    try {
      if (value == null || value.isEmpty) {
        await storage.delete(key: key);
      } else {
        await storage.write(key: key, value: value);
      }
    } catch (e) {
      // The session still works for this run; only persistence is lost.
      debugPrint('TokenStore.write($key) failed: $e');
    }
  }
}
