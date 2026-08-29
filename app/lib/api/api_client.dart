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
  ApiClient({
    Uri? baseUrl,
    http.Client? httpClient,
    this.token,
    this.refreshToken,
  }) : baseUrl = baseUrl ?? defaultBaseUrl(),
       _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;

  /// Short-lived access token sent as `Authorization: Bearer <token>`.
  String? token;

  /// Long-lived, single-use credential sent only to the refresh endpoint.
  String? refreshToken;

  bool get hasToken => token?.isNotEmpty ?? false;

  /// Persists a rotated pair before the original request is retried.
  Future<void> Function(AuthSession session)? onSessionRefreshed;

  /// Invoked only when refresh is absent or rejected, so the app can clear the
  /// secure store and return to the login screen.
  Future<void> Function()? onUnauthorized;

  Future<AuthSession>? _refreshInFlight;

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

  /// Identifies this install in the connected-devices list.
  ///
  /// The http package's default agent is the same string on every platform,
  /// which made every row read "Aplicativo" and defeated the point of the
  /// screen. Browsers forbid setting this header, so web keeps the default.
  static String get _userAgent {
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iPhone',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => 'Fuchsia',
    };
    return 'Diarias/$appVersion ($platform)';
  }

  /// Bumped by hand; only ever shown to the user next to a device.
  static const appVersion = '1.0.0';

  Map<String, String> _headersFor(String? bearer) => {
    'Content-Type': 'application/json; charset=utf-8',
    if (!kIsWeb) 'User-Agent': _userAgent,
    if (bearer case final t? when t.isNotEmpty) 'Authorization': 'Bearer $t',
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
      // A 401 here means "wrong password", not "access token expired".
      handleUnauthorized: false,
      includeAccessToken: false,
    );
    final session = AuthSession.fromJson(body as Map<String, dynamic>);
    _useSession(session);
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
      clearSession();
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
    );
    // The server drops every session on a password change, including this one.
    clearSession();
  }

  /// The devices currently signed in to this account.
  Future<List<SessionInfo>> listSessions() async {
    final body = await _send('GET', '/api/v1/auth/sessions');
    return (body as List<dynamic>)
        .map((s) => SessionInfo.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<void> revokeSession(String id) async {
    await _send('DELETE', '/api/v1/auth/sessions/$id');
  }

  /// Signs out every device except this one.
  Future<int> revokeOtherSessions() async {
    final body = await _send('DELETE', '/api/v1/auth/sessions');
    return ((body as Map<String, dynamic>)['revoked'] as num?)?.toInt() ?? 0;
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
    String? phone,
  }) async {
    final body = await _send(
      'PATCH',
      '/api/v1/providers/$id',
      // Null-aware entries: an omitted field means "leave it as it is",
      // matching the backend's PATCH semantics.
      body: {
        'name': ?name,
        'default_rate_cents': ?defaultRateCents,
        'phone': ?phone,
      },
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
    EntryKind kind = EntryKind.full,
    int? valueCents,
  }) async {
    final body = await _send(
      'PUT',
      '/api/v1/entries',
      body: {
        'provider_id': providerId,
        'date': dateKey(date),
        'kind': kind.wire,
        // Omitted so the server derives it from the kind and her rate.
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
    // False only for credential endpoints whose own 401 must be returned to
    // the caller without recursively trying to refresh.
    bool handleUnauthorized = true,
    bool includeAccessToken = true,
    // Every application request is retried at most once after refresh.
    bool retryAfterRefresh = true,
  }) async {
    final uri = baseUrl.replace(
      path: path,
      queryParameters: query?.isEmpty ?? true ? null : query,
    );
    final sentToken = includeAccessToken ? token : null;
    final request = http.Request(method, uri)
      ..headers.addAll(_headersFor(sentToken));
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

    dynamic decoded;
    if (response.bodyBytes.isNotEmpty) {
      // Decode explicitly as UTF-8: http defaults to latin-1 when the response
      // has no charset, which would mangle "diárias".
      final text = utf8.decode(response.bodyBytes);
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        if (response.statusCode < 400) {
          throw ApiException(
            'Resposta inesperada da API (${response.statusCode}).',
            statusCode: response.statusCode,
          );
        }
      }
    }

    if (response.statusCode >= 400) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message'] as String?
          : null;

      if (response.statusCode == 401 && handleUnauthorized) {
        if (retryAfterRefresh) {
          // Another concurrent request may already have refreshed while this
          // response was in flight. Retry with its new access token instead of
          // rotating the refresh token for a second time.
          if (token != null && token != sentToken) {
            return _send(
              method,
              path,
              query: query,
              body: body,
              handleUnauthorized: handleUnauthorized,
              includeAccessToken: includeAccessToken,
              retryAfterRefresh: false,
            );
          }

          if (refreshToken?.isNotEmpty ?? false) {
            try {
              await _refreshSession();
            } on ApiUnauthorized {
              await _invalidateSession();
              rethrow;
            }
            return _send(
              method,
              path,
              query: query,
              body: body,
              handleUnauthorized: handleUnauthorized,
              includeAccessToken: includeAccessToken,
              retryAfterRefresh: false,
            );
          }
        }

        final error = ApiUnauthorized(message ?? 'Sessão expirada.');
        await _invalidateSession();
        throw error;
      }

      throw _errorFor(response, message);
    }

    if (response.statusCode == 204 || response.bodyBytes.isEmpty) return null;
    return decoded;
  }

  Future<AuthSession> _refreshSession() {
    final current = _refreshInFlight;
    if (current != null) return current;

    late final Future<AuthSession> refresh;
    refresh = _performRefresh().whenComplete(() {
      if (identical(_refreshInFlight, refresh)) _refreshInFlight = null;
    });
    _refreshInFlight = refresh;
    return refresh;
  }

  Future<AuthSession> _performRefresh() async {
    final credential = refreshToken;
    if (credential == null || credential.isEmpty) {
      throw ApiUnauthorized('Refresh token ausente.');
    }

    final body = await _send(
      'POST',
      '/api/v1/auth/refresh',
      body: {'refresh_token': credential},
      handleUnauthorized: false,
      includeAccessToken: false,
      retryAfterRefresh: false,
    );
    final session = AuthSession.fromJson(body as Map<String, dynamic>);
    _useSession(session);
    await onSessionRefreshed?.call(session);
    return session;
  }

  void _useSession(AuthSession session) {
    token = session.token;
    refreshToken = session.refreshToken;
  }

  void clearSession() {
    token = null;
    refreshToken = null;
  }

  Future<void> _invalidateSession() async {
    clearSession();
    await onUnauthorized?.call();
  }

  /// Maps a failed response onto the right exception type.
  ApiException _errorFor(http.Response response, String? message) {
    final fallback = 'A API respondeu ${response.statusCode}.';

    switch (response.statusCode) {
      case 401:
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
    this.refreshToken,
    this.refreshExpiresAt,
    required this.user,
  });

  final String token;
  final DateTime expiresAt;
  final String? refreshToken;
  final DateTime? refreshExpiresAt;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    token: json['token'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String),
    refreshToken: json['refresh_token'] as String?,
    refreshExpiresAt: switch (json['refresh_expires_at']) {
      final String value => DateTime.parse(value),
      _ => null,
    },
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

/// One signed-in device, for the account screen.
@immutable
class SessionInfo {
  const SessionInfo({
    required this.id,
    required this.userAgent,
    required this.createdAt,
    required this.lastSeenAt,
    required this.current,
  });

  final String id;

  /// Client-supplied and therefore untrusted — shown, never acted on.
  final String userAgent;
  final DateTime createdAt;
  final DateTime lastSeenAt;

  /// True for the device asking, which must not offer to revoke itself.
  final bool current;

  /// A readable device name, since the raw user agent is noise.
  String get label {
    final ua = userAgent.toLowerCase();
    if (ua.contains('android')) return 'Android';
    if (ua.contains('iphone') || ua.contains('ios')) return 'iPhone';
    if (ua.contains('mac')) return 'Mac';
    if (ua.contains('windows')) return 'Windows';
    if (ua.contains('linux')) return 'Linux';
    // Sessions created before the app identified itself.
    if (ua.contains('dart')) return 'Aparelho antigo';
    return userAgent.isEmpty ? 'Aparelho desconhecido' : userAgent;
  }

  factory SessionInfo.fromJson(Map<String, dynamic> json) => SessionInfo(
    id: json['id'] as String,
    userAgent: (json['user_agent'] as String?) ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
    lastSeenAt: DateTime.parse(json['last_seen_at'] as String),
    current: (json['current'] as bool?) ?? false,
  );
}
