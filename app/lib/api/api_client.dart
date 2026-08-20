import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Thrown for any failed API call. [isNetwork] separates "the server said no"
/// from "we never reached the server", which the UI words differently.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.isNetwork = false});

  final String message;
  final int? statusCode;
  final bool isNetwork;

  @override
  String toString() => message;
}

/// The session is gone — expired, revoked, or the password was changed. The app
/// reacts by returning to the login screen rather than showing an error.
class ApiUnauthorized extends ApiException {
  ApiUnauthorized(super.message) : super(statusCode: 401);
}

/// Too many failed logins. [retryAfter] is the server's Retry-After, when sent.
class ApiTooManyAttempts extends ApiException {
  ApiTooManyAttempts(super.message, {this.retryAfter}) : super(statusCode: 429);

  final Duration? retryAfter;
}

/// HTTP client for the Go backend.
class ApiClient {
  ApiClient({Uri? baseUrl, http.Client? httpClient, this.token})
    : baseUrl = baseUrl ?? defaultBaseUrl(),
      _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;

  /// Session token, sent as `Authorization: Bearer <token>`. Set on login,
  /// cleared on logout or when the server rejects it.
  String? token;

  bool get hasToken => token?.isNotEmpty ?? false;

  /// Invoked when any call is rejected with 401, so the app can drop the stored
  /// token and return to the login screen from wherever it was.
  void Function()? onUnauthorized;

  static const _timeout = Duration(seconds: 15);

  /// The deployed API. HTTPS is not negotiable here: the login sends a password
  /// in the request body, over the public internet.
  static const productionUrl = 'https://colaboradores.fca.dev.br';

  /// Where the API lives by default: production.
  ///
  /// Override at build time with one of the checked-in configs rather than
  /// editing this file:
  ///
  ///   flutter run --dart-define-from-file=config/local.json   # API na VM, pela LAN
  ///   flutter run --dart-define-from-file=config/prod.json    # explicitamente produção
  ///
  /// Because production is the default, a plain `flutter run` writes to real
  /// data — use config/local.json while developing.
  static Uri defaultBaseUrl() {
    const configured = String.fromEnvironment('DIARIAS_API_URL');
    if (configured.isNotEmpty) return Uri.parse(configured);
    return Uri.parse(productionUrl);
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json; charset=utf-8',
    if (token case final t? when t.isNotEmpty) 'Authorization': 'Bearer $t',
  };

  void dispose() => _http.close();

  // ------------------------------------------------------------------ auth --

  /// Exchanges credentials for a session token. On success the token is stored
  /// on this client, so subsequent calls are authenticated.
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final body = await _send(
      'POST',
      '/api/v1/auth/login',
      body: {'username': username, 'password': password},
      // A 401 here means "wrong password", not "session expired" — it must not
      // trigger the global logout handler.
      isLogin: true,
    );
    final session = AuthSession.fromJson(body as Map<String, dynamic>);
    token = session.token;
    return session;
  }

  /// Confirms a stored token is still valid and returns its owner.
  Future<AuthUser> me() async {
    final body = await _send('GET', '/api/v1/auth/me');
    return AuthUser.fromJson(body as Map<String, dynamic>);
  }

  /// Ends the session server-side. The local token is cleared either way: if
  /// the server cannot be reached, the user still expects to be logged out.
  Future<void> logout() async {
    try {
      await _send('POST', '/api/v1/auth/logout');
    } finally {
      token = null;
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _send(
      'POST',
      '/api/v1/auth/password',
      body: {'current_password': currentPassword, 'new_password': newPassword},
      isLogin: true,
    );
    // The server drops every session on a password change, including this one.
    token = null;
  }

  // ------------------------------------------------------------- providers --

  Future<List<Provider>> listProviders() async {
    final body = await _send('GET', '/api/v1/providers');
    return (body as List<dynamic>)
        .map((p) => Provider.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<Provider> createProvider({
    String name = '',
    int defaultRateCents = 0,
  }) async {
    final body = await _send(
      'POST',
      '/api/v1/providers',
      body: {'name': name, 'default_rate_cents': defaultRateCents},
    );
    return Provider.fromJson(body as Map<String, dynamic>);
  }

  Future<Provider> updateProvider(
    String id, {
    String? name,
    int? defaultRateCents,
  }) async {
    final body = await _send(
      'PATCH',
      '/api/v1/providers/$id',
      // Null-aware entries: an omitted field means "leave it as it is",
      // matching the backend's PATCH semantics.
      body: {'name': ?name, 'default_rate_cents': ?defaultRateCents},
    );
    return Provider.fromJson(body as Map<String, dynamic>);
  }

  Future<void> deleteProvider(String id) async {
    await _send('DELETE', '/api/v1/providers/$id');
  }

  // --------------------------------------------------------------- entries --

  Future<List<WorkEntry>> listEntries({
    required int year,
    required int month,
  }) async {
    final body = await _send(
      'GET',
      '/api/v1/entries',
      query: {'year': '$year', 'month': '$month'},
    );
    return (body as List<dynamic>)
        .map((e) => WorkEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Marks [date] as worked. A null [valueCents] adopts the prestadora's
  /// current default rate, which is what tapping a fresh checkbox should do.
  Future<WorkEntry> upsertEntry({
    required String providerId,
    required DateTime date,
    int? valueCents,
  }) async {
    final body = await _send(
      'PUT',
      '/api/v1/entries',
      body: {
        'provider_id': providerId,
        'date': dateKey(date),
        // Omitted so the server falls back to the prestadora's default rate.
        'value_cents': ?valueCents,
      },
    );
    return WorkEntry.fromJson(body as Map<String, dynamic>);
  }

  Future<void> deleteEntry({
    required String providerId,
    required DateTime date,
  }) async {
    await _send(
      'DELETE',
      '/api/v1/entries',
      query: {'provider_id': providerId, 'date': dateKey(date)},
    );
  }

  // -------------------------------------------------------------- closings --

  Future<MonthClosing> monthClosing({
    required int year,
    required int month,
  }) async {
    final body = await _send('GET', '/api/v1/months/$year/$month');
    return MonthClosing.fromJson(body as Map<String, dynamic>);
  }

  /// Both payment calls return the whole refreshed month, so the caller can
  /// update the header total and every card from one response.
  Future<MonthClosing> markPaid({
    required int year,
    required int month,
    required String providerId,
  }) async {
    final body = await _send(
      'PUT',
      '/api/v1/months/$year/$month/providers/$providerId/payment',
    );
    return MonthClosing.fromJson(body as Map<String, dynamic>);
  }

  Future<MonthClosing> unmarkPaid({
    required int year,
    required int month,
    required String providerId,
  }) async {
    final body = await _send(
      'DELETE',
      '/api/v1/months/$year/$month/providers/$providerId/payment',
    );
    return MonthClosing.fromJson(body as Map<String, dynamic>);
  }

  // --------------------------------------------------------------- plumbing --

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    // Set on the credential endpoints, where a 401 means "wrong password"
    // rather than "your session died" and must not log the app out.
    bool isLogin = false,
  }) async {
    final uri = baseUrl.replace(
      path: path,
      queryParameters: query?.isEmpty ?? true ? null : query,
    );
    final request = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
      // http.ClientException and TimeoutException both mean "never got an
      // answer". dart:io's SocketException is deliberately not referenced here
      // so this file still compiles for Flutter Web.
    } on http.ClientException catch (e) {
      throw ApiException(
        'Não foi possível falar com o servidor (${e.message}).',
        isNetwork: true,
      );
    } on TimeoutException {
      throw ApiException(
        'O servidor demorou demais para responder.',
        isNetwork: true,
      );
    } catch (_) {
      throw ApiException(
        'Não foi possível falar com o servidor. Verifique se a API está no ar.',
        isNetwork: true,
      );
    }

    if (response.statusCode == 204 || response.bodyBytes.isEmpty) {
      if (response.statusCode >= 400) {
        throw _errorFor(response, null, isLogin);
      }
      return null;
    }

    // Decode explicitly as UTF-8: http defaults to latin-1 when the response
    // has no charset, which would mangle "diárias".
    final text = utf8.decode(response.bodyBytes);
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw ApiException(
        'Resposta inesperada da API (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 400) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message'] as String?
          : null;
      throw _errorFor(response, message, isLogin);
    }
    return decoded;
  }

  /// Maps a failed response onto the right exception type.
  ApiException _errorFor(
    http.Response response,
    String? message,
    bool isLogin,
  ) {
    final fallback = 'A API respondeu ${response.statusCode}.';

    switch (response.statusCode) {
      case 401:
        if (!isLogin) {
          // The stored token is no longer good; drop it and let the app show
          // the login screen instead of an error the user cannot act on.
          token = null;
          onUnauthorized?.call();
        }
        return ApiUnauthorized(message ?? 'Sessão expirada.');
      case 429:
        final seconds = int.tryParse(response.headers['retry-after'] ?? '');
        return ApiTooManyAttempts(
          message ?? 'Tentativas demais. Aguarde um pouco.',
          retryAfter: seconds == null ? null : Duration(seconds: seconds),
        );
      default:
        return ApiException(
          message ?? fallback,
          statusCode: response.statusCode,
        );
    }
  }
}

/// The successful result of a login.
@immutable
class AuthSession {
  const AuthSession({
    required this.token,
    required this.expiresAt,
    required this.user,
  });

  final String token;
  final DateTime expiresAt;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    token: json['token'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
    user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
  );
}

@immutable
class AuthUser {
  const AuthUser({required this.id, required this.username});

  final String id;
  final String username;

  factory AuthUser.fromJson(Map<String, dynamic> json) =>
      AuthUser(id: json['id'] as String, username: json['username'] as String);
}
