import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'token_store.dart';

enum AuthStatus {
  /// Still checking for a stored token — shows the splash, never the login
  /// form, so a logged-in user does not see it flash on every launch.
  checking,
  loggedOut,
  loggedIn,
}

/// Owns the session: restoring it at launch, logging in, logging out.
class AuthController extends ChangeNotifier {
  AuthController({required this.api, this.store = const TokenStore()}) {
    // A 401 first goes through ApiClient's refresh flow. Only an absent or
    // rejected refresh token lands here, from wherever the request was made.
    api.onUnauthorized = _onSessionLost;
    api.onSessionRefreshed = _onSessionRefreshed;
  }

  final ApiClient api;
  final TokenStore store;

  AuthStatus _status = AuthStatus.checking;
  AuthStatus get status => _status;

  AuthUser? _user;
  AuthUser? get user => _user;

  /// Set when the session ended on its own rather than by the user logging
  /// out, so the login screen can explain why they are back there.
  String? _notice;
  String? get notice => _notice;

  bool _busy = false;
  bool get busy => _busy;

  /// Restores a stored session, verifying it against the server before trusting
  /// it. An expired access token is refreshed transparently by api.me().
  Future<void> restore() async {
    final tokens = await store.read();
    if (tokens == null) {
      _set(AuthStatus.loggedOut);
      return;
    }

    api.token = tokens.accessToken;
    api.refreshToken = tokens.refreshToken;
    try {
      _user = await api.me();
      _set(AuthStatus.loggedIn);
    } on ApiUnauthorized {
      // Token no longer valid; start clean.
      await store.clear();
      api.clearSession();
      _set(AuthStatus.loggedOut);
    } on ApiException {
      // The server is unreachable, so the token could not be checked — but a
      // stored credential plus the cached month is far more useful than a login
      // screen the user cannot get past while the wifi is down. The session is
      // kept optimistically; the first 401 once the network returns will refresh
      // it or sign out properly.
      _user = null;
      _set(AuthStatus.loggedIn);
    }
  }

  /// Attempts a login. Returns null on success, or a message to show.
  Future<String?> login(String username, String password) async {
    if (_busy) return null;
    _busy = true;
    _notice = null;
    notifyListeners();

    try {
      final session = await api.login(
        username: username.trim(),
        password: password,
      );
      await _persistSession(session);
      _user = session.user;
      _set(AuthStatus.loggedIn);
      return null;
    } on ApiTooManyAttempts catch (e) {
      final wait = e.retryAfter;
      return wait == null ? e.message : '${e.message} (${_humanWait(wait)})';
    } on ApiUnauthorized {
      // Deliberately not "user not found" vs "wrong password" — the server does
      // not distinguish them and neither should the UI.
      return 'Usuário ou senha inválidos.';
    } on ApiException catch (e) {
      return e.message;
    } finally {
      _busy = false;
      // A rejected attempt must land in a definite state. Left in `checking`
      // — which is where the controller starts — the app would sit on the
      // splash screen instead of showing the form again.
      if (_status != AuthStatus.loggedIn) _status = AuthStatus.loggedOut;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();

    try {
      await api.logout();
    } on ApiException {
      // Already handled: the local token is cleared regardless.
    } finally {
      await store.clear();
      api.clearSession();
      _user = null;
      _notice = null;
      _busy = false;
      _set(AuthStatus.loggedOut);
    }
  }

  /// Fills in who is signed in, when a session was restored offline and the
  /// server could not be asked at the time.
  ///
  /// Safe to call repeatedly: it does nothing once the user is known, and a
  /// failure leaves the session alone rather than signing anyone out.
  Future<void> ensureUserLoaded() async {
    if (_user != null || _status != AuthStatus.loggedIn) return;
    try {
      _user = await api.me();
      notifyListeners();
    } on ApiException {
      // Still unreachable, or the session died — the 401 path handles the
      // latter on its own.
    }
  }

  Future<void> _onSessionRefreshed(AuthSession session) async {
    await _persistSession(session);
    _user = session.user;
  }

  Future<void> _persistSession(AuthSession session) => store.write(
    accessToken: session.token,
    refreshToken: session.refreshToken,
  );

  /// Called when both access and refresh credentials can no longer recover.
  Future<void> _onSessionLost() async {
    await store.clear();
    if (_status != AuthStatus.loggedIn) return;
    _user = null;
    _notice = 'Sua sessão expirou. Entre de novo.';
    _set(AuthStatus.loggedOut);
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  void _set(AuthStatus status) {
    _status = status;
    notifyListeners();
  }

  static String _humanWait(Duration d) {
    if (d.inMinutes >= 1) return 'aguarde ${d.inMinutes} min';
    return 'aguarde ${d.inSeconds}s';
  }
}
