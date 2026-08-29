import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'auth/auth_controller.dart';
import 'firebase/firebase_setup.dart';
import 'notifications/reminder_service.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Best-effort: if Firebase cannot start, the app still runs. Awaited so the
  // crash handlers are in place before any app code executes.
  await FirebaseSetup.initialize();
  runApp(const DiariasApp());
}

class DiariasApp extends StatefulWidget {
  const DiariasApp({super.key});

  @override
  State<DiariasApp> createState() => _DiariasAppState();
}

class _DiariasAppState extends State<DiariasApp> {
  late final ApiClient _api;
  late final AuthController _auth;
  late final AppState _state;
  late final ReminderService _reminders;

  @override
  void initState() {
    super.initState();
    _api = ApiClient();
    _auth = AuthController(api: _api);
    _reminders = ReminderService(api: _api);
    _state = AppState(api: _api);

    _auth.addListener(_onAuthChanged);
    // A session restored while offline has no user attached yet; once data
    // flows again, fill in who it belongs to.
    _state.addListener(_onStateChanged);
    // Checks for a stored token before deciding which screen to show.
    _auth.restore();
    // Re-registers the push token, in case FCM rotated it while the app was
    // closed. A no-op when the user has reminders off.
    _reminders.refresh();
  }

  void _onStateChanged() {
    if (!_state.offlineMode && _state.initialLoadDone) {
      _auth.ensureUserLoaded();
    }
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    _auth.removeListener(_onAuthChanged);
    _auth.dispose();
    _state.dispose();
    _api.dispose();
    super.dispose();
  }

  AuthStatus? _lastStatus;

  /// Data is loaded on sign-in and dropped on sign-out, so a second account
  /// never sees the previous one's screen contents before its own load lands.
  void _onAuthChanged() {
    final status = _auth.status;
    if (status == _lastStatus) return;
    _lastStatus = status;

    switch (status) {
      case AuthStatus.loggedIn:
        _state.load();
        // Crash reports become answerable when you know whose phone it was.
        FirebaseSetup.setUser(_auth.user?.username);
      case AuthStatus.loggedOut:
        _state.reset();
        FirebaseSetup.setUser(null);
      case AuthStatus.checking:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diárias',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      home: ListenableBuilder(
        listenable: _auth,
        builder: (context, _) => switch (_auth.status) {
          AuthStatus.checking => const _SplashScreen(),
          AuthStatus.loggedOut => LoginScreen(auth: _auth),
          AuthStatus.loggedIn => AuthScope(
            auth: _auth,
            child: ReminderScope(
              reminders: _reminders,
              child: AppScope(notifier: _state, child: const HomeScreen()),
            ),
          ),
        },
      ),
    );
  }
}

/// Shown only while a stored token is being checked — brief, and on the brand
/// gradient so it reads as the app starting rather than a blank frame.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: DsGradients.hero),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
    );
  }
}

/// Makes the single [AppState] available to the widget tree and rebuilds
/// dependents when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    super.key,
    required AppState super.notifier,
    required super.child,
  });

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope?.notifier != null, 'No AppScope found in context');
    return scope!.notifier!;
  }
}

/// Exposes the session to screens that need to show who is signed in, or sign
/// them out.
class AuthScope extends InheritedWidget {
  const AuthScope({super.key, required this.auth, required super.child});

  final AuthController auth;

  static AuthController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'No AuthScope found in context');
    return scope!.auth;
  }

  /// Returns null outside a session — lets widgets shared with the logged-out
  /// tree stay usable.
  static AuthController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScope>()?.auth;

  @override
  bool updateShouldNotify(AuthScope oldWidget) => auth != oldWidget.auth;
}

/// Exposes the reminder scheduler to the account screen.
class ReminderScope extends InheritedWidget {
  const ReminderScope({
    super.key,
    required this.reminders,
    required super.child,
  });

  final ReminderService reminders;

  static ReminderService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReminderScope>()?.reminders;

  @override
  bool updateShouldNotify(ReminderScope oldWidget) =>
      reminders != oldWidget.reminders;
}
