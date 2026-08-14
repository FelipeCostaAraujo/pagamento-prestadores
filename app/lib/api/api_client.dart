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

/// HTTP client for the Go backend.
class ApiClient {
  ApiClient({Uri? baseUrl, http.Client? httpClient, this.token})
    : baseUrl = baseUrl ?? defaultBaseUrl(),
      _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;

  /// Sent as `Authorization: Bearer <token>` when set, matching the backend's
  /// optional `DIARIAS_API_TOKEN`.
  final String? token;

  static const _timeout = Duration(seconds: 15);

  /// Where the API lives by default.
  ///
  /// Overridable at build time with `--dart-define=DIARIAS_API_URL=...`.
  /// The Android emulator reaches the host machine through 10.0.2.2 rather than
  /// localhost, so it gets its own default.
  static Uri defaultBaseUrl() {
    const configured = String.fromEnvironment('DIARIAS_API_URL');
    if (configured.isNotEmpty) return Uri.parse(configured);

    final host =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';
    return Uri.parse('http://$host:8080');
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json; charset=utf-8',
    if (token case final t? when t.isNotEmpty) 'Authorization': 'Bearer $t',
  };

  void dispose() => _http.close();

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
        throw ApiException(
          'A API respondeu ${response.statusCode}.',
          statusCode: response.statusCode,
        );
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
      throw ApiException(
        message ?? 'A API respondeu ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}
