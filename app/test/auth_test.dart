import 'dart:convert';

import 'package:diarias/api/api_client.dart';
import 'package:diarias/auth/auth_controller.dart';
import 'package:diarias/auth/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An in-memory stand-in for the platform keystore.
class _FakeTokenStore implements TokenStore {
  String? stored;

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String token) async => stored = token;

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
  List<String>? seenAuthHeaders,
}) {
  return MockClient((request) async {
    seenAuthHeaders?.add(request.headers['Authorization'] ?? '');

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
          'token': token,
          'expires_at': '2026-09-11T00:00:00Z',
          'user': _user,
        }, 200);

      case '/api/v1/auth/me':
        if (request.headers['Authorization'] != 'Bearer $token') {
          return _json({
            'code': 'unauthorized',
            'message': 'sessão inválida ou expirada',
          }, 401);
        }
        return _json(_user, 200);

      case '/api/v1/auth/logout':
        return http.Response('', 204);

      case '/api/v1/providers':
        if (request.headers['Authorization'] != 'Bearer $token') {
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
    api: ApiClient(
      baseUrl: Uri.parse('http://test.local'),
      httpClient: client,
    ),
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
    expect(store.stored, 'token-abc');
    expect(auth.api.token, 'token-abc');
  });

  test('a wrong password reports a generic failure and stores nothing', () async {
    final store = _FakeTokenStore();
    final auth = _controller(_authApi(), store);

    final failure = await auth.login('felipe', 'errada');

    // The message must not say whether the username exists.
    expect(failure, 'Usuário ou senha inválidos.');
    expect(auth.status, AuthStatus.loggedOut);
    expect(store.stored, isNull);
  });

  test('restore accepts a stored token the server still recognises', () async {
    final store = _FakeTokenStore()..stored = 'token-abc';
    final auth = _controller(_authApi(), store);

    await auth.restore();

    expect(auth.status, AuthStatus.loggedIn);
    expect(auth.user?.username, 'felipe');
  });

  test('restore discards a token the server rejects', () async {
    final store = _FakeTokenStore()..stored = 'token-antigo';
    final auth = _controller(_authApi(), store);

    await auth.restore();

    expect(auth.status, AuthStatus.loggedOut);
    expect(store.stored, isNull, reason: 'a rejected token must not be kept');
  });

  test('restore keeps the token when the server is unreachable', () async {
    final store = _FakeTokenStore()..stored = 'token-abc';
    final offline = MockClient(
      (_) async => throw http.ClientException('connection refused'),
    );
    final auth = _controller(offline, store);

    await auth.restore();

    // Being offline is not proof the session died — throwing the token away
    // would force a needless re-login once the network comes back.
    expect(auth.status, AuthStatus.loggedOut);
    expect(store.stored, 'token-abc');
  });

  test('every authenticated request carries the bearer token', () async {
    final headers = <String>[];
    final store = _FakeTokenStore();
    final auth = _controller(_authApi(seenAuthHeaders: headers), store);

    await auth.login('felipe', 'senha-muito-longa');
    headers.clear();
    await auth.api.listProviders();

    expect(headers, ['Bearer token-abc']);
  });

  test('a 401 mid-session logs the app out and clears the token', () async {
    final store = _FakeTokenStore();
    final auth = _controller(_authApi(), store);
    await auth.login('felipe', 'senha-muito-longa');
    expect(auth.status, AuthStatus.loggedIn);

    // Simulate the session being revoked server-side.
    auth.api.token = 'token-revogado';
    await expectLater(auth.api.listProviders(), throwsA(isA<ApiUnauthorized>()));

    expect(auth.status, AuthStatus.loggedOut);
    expect(store.stored, isNull);
    expect(auth.notice, isNotNull, reason: 'the login screen should explain why');
  });

  test('logout clears the stored token', () async {
    final store = _FakeTokenStore();
    final auth = _controller(_authApi(), store);
    await auth.login('felipe', 'senha-muito-longa');

    await auth.logout();

    expect(auth.status, AuthStatus.loggedOut);
    expect(store.stored, isNull);
    expect(auth.api.token, isNull);
    expect(auth.user, isNull);
  });

  test('logout clears the local token even if the server is unreachable', () async {
    final store = _FakeTokenStore()..stored = 'token-abc';
    var failNext = false;
    final client = MockClient((request) async {
      if (failNext) throw http.ClientException('connection refused');
      return _json({
        'token': 'token-abc',
        'expires_at': '2026-09-11T00:00:00Z',
        'user': _user,
      }, 200);
    });

    final auth = _controller(client, store);
    await auth.login('felipe', 'senha-muito-longa');
    failNext = true;

    await auth.logout();

    expect(auth.status, AuthStatus.loggedOut);
    expect(store.stored, isNull);
  });

  test('too many attempts surfaces the wait instead of a credentials error', () async {
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
  });
}
