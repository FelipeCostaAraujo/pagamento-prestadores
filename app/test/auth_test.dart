import 'dart:convert';

import 'package:diarias/api/api_client.dart';
import 'package:diarias/auth/auth_controller.dart';
import 'package:diarias/auth/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An in-memory stand-in for the platform keystore.
class _FakeTokenStore implements TokenStore {
  StoredSessionTokens? stored;

  @override
  Future<StoredSessionTokens?> read() async => stored;

  @override
  Future<void> write({
    required String accessToken,
    String? refreshToken,
  }) async => stored = StoredSessionTokens(
    accessToken: accessToken,
    refreshToken: refreshToken,
  );

  @override
  Future<void> clear() async => stored = null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> get _user => {
  'id': 'u1',
  'username': 'felipe',
  'created_at': '2026-08-12T00:00:00Z',
};

http.Response _json(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Serves a backend that accepts one credential pair and one token.
http.Client _authApi({
  String password = 'senha-muito-longa',
  String token = 'token-abc',
  String refreshToken = 'refresh-abc',
  List<String>? seenAuthHeaders,
  List<String>? seenPaths,
  Duration refreshDelay = Duration.zero,
}) {
  var currentToken = token;
  var currentRefreshToken = refreshToken;
  var refreshCount = 0;

  return MockClient((request) async {
    seenAuthHeaders?.add(request.headers['Authorization'] ?? '');
    seenPaths?.add(request.url.path);

    switch (request.url.path) {
      case '/api/v1/auth/login':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['password'] != password) {
          return _json({
            'code': 'unauthorized',
            'message': 'usuário ou senha inválidos',
          }, 401);
        }
        return _json({
          'token': currentToken,
          'expires_at': '2026-08-28T20:00:00Z',
          'refresh_token': currentRefreshToken,
          'refresh_expires_at': '2026-09-27T20:00:00Z',
          'user': _user,
        }, 200);

      case '/api/v1/auth/refresh':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final presented = body['refresh_token'];
        if (presented != currentRefreshToken) {
          return _json({
            'code': 'unauthorized',
            'message': 'refresh token inválido ou expirado',
          }, 401);
        }
        if (refreshDelay > Duration.zero) {
          await Future<void>.delayed(refreshDelay);
        }
        // Validate again after the artificial delay, matching atomic token
        // consumption by the backend.
        if (presented != currentRefreshToken) {
          return _json({
            'code': 'unauthorized',
            'message': 'refresh token inválido ou expirado',
          }, 401);
        }
        refreshCount++;
        currentToken = '$token-r$refreshCount';
        currentRefreshToken = '$refreshToken-r$refreshCount';
        return _json({
          'token': currentToken,
          'expires_at': '2026-08-28T20:15:00Z',
          'refresh_token': currentRefreshToken,
          'refresh_expires_at': '2026-09-27T20:00:00Z',
          'user': _user,
        }, 200);

      case '/api/v1/auth/me':
        if (request.headers['Authorization'] != 'Bearer $currentToken') {
          return _json({
            'code': 'unauthorized',
            'message': 'sessão inválida ou expirada',
          }, 401);
        }
        return _json(_user, 200);

      case '/api/v1/auth/logout':
        return http.Response('', 204);

      case '/api/v1/providers':
        if (request.headers['Authorization'] != 'Bearer $currentToken') {
          return _json({
            'code': 'unauthorized',
            'message': 'sessão inválida ou expirada',
          }, 401);
        }
        return _json(<dynamic>[], 200);

      default:
        return _json(<String, dynamic>{}, 200);
    }
  });
}

AuthController _controller(http.Client client, _FakeTokenStore store) {
  return AuthController(
    api: ApiClient(baseUrl: Uri.parse('http://test.local'), httpClient: client),
    store: store,
  );
}

void main() {
  test('starts logged out when nothing is stored', () async {
    final store = _FakeTokenStore();
    final auth = _controller(_authApi(), store);

    expect(auth.status, AuthStatus.checking);
    await auth.restore();
    expect(auth.status, AuthStatus.loggedOut);
  });

  test('a correct password logs in and persists the token', () async {
    final store = _FakeTokenStore();
    final auth = _controller(_authApi(), store);

    final failure = await auth.login('felipe', 'senha-muito-longa');

    expect(failure, isNull);
    expect(auth.status, AuthStatus.loggedIn);
    expect(auth.user?.username, 'felipe');
    expect(store.stored?.accessToken, 'token-abc');
    expect(store.stored?.refreshToken, 'refresh-abc');
    expect(auth.api.token, 'token-abc');
    expect(auth.api.refreshToken, 'refresh-abc');
  });

  test(
    'a wrong password reports a generic failure and stores nothing',
    () async {
      final store = _FakeTokenStore();
      final auth = _controller(_authApi(), store);

      final failure = await auth.login('felipe', 'errada');

      // The message must not say whether the username exists.
      expect(failure, 'Usuário ou senha inválidos.');
      expect(auth.status, AuthStatus.loggedOut);
      expect(store.stored, isNull);
    },
  );

  test('restore accepts a stored token the server still recognises', () async {
    final store = _FakeTokenStore()
      ..stored = const StoredSessionTokens(
        accessToken: 'token-abc',
        refreshToken: 'refresh-abc',
      );
    final auth = _controller(_authApi(), store);

    await auth.restore();

    expect(auth.status, AuthStatus.loggedIn);
    expect(auth.user?.username, 'felipe');
  });

  test('restore refreshes an expired access token', () async {
    final store = _FakeTokenStore()
      ..stored = const StoredSessionTokens(
        accessToken: 'token-antigo',
        refreshToken: 'refresh-abc',
      );
    final auth = _controller(_authApi(), store);

    await auth.restore();

    expect(auth.status, AuthStatus.loggedIn);
    expect(auth.api.token, 'token-abc-r1');
    expect(store.stored?.accessToken, 'token-abc-r1');
    expect(store.stored?.refreshToken, 'refresh-abc-r1');
  });

  test('restore discards a token pair the server rejects', () async {
    final store = _FakeTokenStore()
      ..stored = const StoredSessionTokens(
        accessToken: 'token-antigo',
        refreshToken: 'refresh-antigo',
      );
    final auth = _controller(_authApi(), store);

    await auth.restore();

    expect(auth.status, AuthStatus.loggedOut);
    expect(
      store.stored,
      isNull,
      reason: 'a rejected token pair must not be kept',
    );
  });

  test(
    'an unreachable server keeps the session so the cache is usable',
    () async {
      // Regression: a cold start with no network dropped straight to the login
      // screen, which made the offline cache unreachable in exactly the
      // situation it exists for.
      final store = _FakeTokenStore()
        ..stored = const StoredSessionTokens(
          accessToken: 'token-abc',
          refreshToken: 'refresh-abc',
        );
      final offline = MockClient(
        (_) async => throw http.ClientException('connection refused'),
      );
      final auth = _controller(offline, store);

      await auth.restore();

      expect(auth.status, AuthStatus.loggedIn);
      expect(store.stored?.accessToken, 'token-abc');
      expect(auth.api.token, 'token-abc', reason: 'needed to retry when back');
    },
  );

  test('every authenticated request carries the bearer token', () async {
    final headers = <String>[];
    final store = _FakeTokenStore();
    final auth = _controller(_authApi(seenAuthHeaders: headers), store);

    await auth.login('felipe', 'senha-muito-longa');
    headers.clear();
    await auth.api.listProviders();

    expect(headers, ['Bearer token-abc']);
  });

  test('a 401 refreshes the session and retries the request once', () async {
    final store = _FakeTokenStore();
    final auth = _controller(_authApi(), store);
    await auth.login('felipe', 'senha-muito-longa');
    expect(auth.status, AuthStatus.loggedIn);

    // Simulate only the short-lived access token expiring server-side.
    auth.api.token = 'token-revogado';
    await auth.api.listProviders();

    expect(auth.status, AuthStatus.loggedIn);
    expect(auth.api.token, 'token-abc-r1');
    expect(auth.api.refreshToken, 'refresh-abc-r1');
    expect(store.stored?.accessToken, 'token-abc-r1');
  });

  test(
    'a rejected refresh token logs the app out and clears both tokens',
    () async {
      final store = _FakeTokenStore();
      final auth = _controller(_authApi(), store);
      await auth.login('felipe', 'senha-muito-longa');

      auth.api.token = 'token-revogado';
      auth.api.refreshToken = 'refresh-revogado';
      await expectLater(
        auth.api.listProviders(),
        throwsA(isA<ApiUnauthorized>()),
      );

      expect(auth.status, AuthStatus.loggedOut);
      expect(store.stored, isNull);
      expect(
        auth.notice,
        isNotNull,
        reason: 'the login screen should explain why',
      );
    },
  );

  test('concurrent 401 responses share one refresh operation', () async {
    final paths = <String>[];
    final store = _FakeTokenStore();
    final auth = _controller(
      _authApi(
        seenPaths: paths,
        refreshDelay: const Duration(milliseconds: 10),
      ),
      store,
    );
    await auth.login('felipe', 'senha-muito-longa');
    paths.clear();
    auth.api.token = 'token-expirado';

    await Future.wait([auth.api.listProviders(), auth.api.listProviders()]);

    expect(paths.where((path) => path == '/api/v1/auth/refresh').length, 1);
    expect(auth.status, AuthStatus.loggedIn);
    expect(auth.api.token, 'token-abc-r1');
  });

  test('logout clears the stored token', () async {
    final store = _FakeTokenStore();
    final auth = _controller(_authApi(), store);
    await auth.login('felipe', 'senha-muito-longa');

    await auth.logout();

    expect(auth.status, AuthStatus.loggedOut);
    expect(store.stored, isNull);
    expect(auth.api.token, isNull);
    expect(auth.api.refreshToken, isNull);
    expect(auth.user, isNull);
  });

  test(
    'logout clears the local token even if the server is unreachable',
    () async {
      final store = _FakeTokenStore()
        ..stored = const StoredSessionTokens(
          accessToken: 'token-abc',
          refreshToken: 'refresh-abc',
        );
      var failNext = false;
      final client = MockClient((request) async {
        if (failNext) throw http.ClientException('connection refused');
        return _json({
          'token': 'token-abc',
          'expires_at': '2026-09-11T00:00:00Z',
          'refresh_token': 'refresh-abc',
          'refresh_expires_at': '2026-09-27T00:00:00Z',
          'user': _user,
        }, 200);
      });

      final auth = _controller(client, store);
      await auth.login('felipe', 'senha-muito-longa');
      failNext = true;

      await auth.logout();

      expect(auth.status, AuthStatus.loggedOut);
      expect(store.stored, isNull);
    },
  );

  test(
    'too many attempts surfaces the wait instead of a credentials error',
    () async {
      final store = _FakeTokenStore();
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'too_many_attempts',
            'message': 'tentativas demais.',
          }),
          429,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'retry-after': '120',
          },
        ),
      );
      final auth = _controller(client, store);

      final failure = await auth.login('felipe', 'seja-la-o-que-for');

      expect(failure, contains('tentativas demais'));
      expect(failure, contains('2 min'));
      expect(auth.status, AuthStatus.loggedOut);
    },
  );
}
