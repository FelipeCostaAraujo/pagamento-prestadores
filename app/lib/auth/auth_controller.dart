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
    // Any request rejected with 401 lands here, from wherever it was made.
    api.onUnauthorized = _onSessionLost;
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
  /// it — a token can have been revoked or expired while the app was closed.
  Future<void> restore() async {
    final token = await store.read();
    if (token == null) {
      _set(AuthStatus.loggedOut);
      return;
    }

    api.token = token;
    try {
      _user = await api.me();
      _set(AuthStatus.loggedIn);
    } on ApiUnauthorized {
      // Token no longer valid; start clean.
      await store.clear();
      api.token = null;
      _set(AuthStatus.loggedOut);
    } on ApiException {
      // The server is unreachable. Keep the token — it may well still be good —
      // and let the user retry from the login screen rather than silently
      // discarding a valid session because the wifi was down.
      api.token = null;
      _set(AuthStatus.loggedOut);
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
      await store.write(session.token);
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
      api.token = null;
      _user = null;
      _notice = null;
      _busy = false;
      _set(AuthStatus.loggedOut);
    }
  }

  /// Called when the API reports 401 mid-session.
  void _onSessionLost() {
    if (_status != AuthStatus.loggedIn) return;
    store.clear();
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
