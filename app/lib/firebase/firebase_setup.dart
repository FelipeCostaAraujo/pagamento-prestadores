import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../firebase_options.dart';

/// Firebase wiring, kept in one place and deliberately optional.
///
/// Everything here is best-effort: a household app that cannot reach Google
/// must still open and let someone mark a day. Nothing in this file is allowed
/// to throw into startup.
abstract final class FirebaseSetup {
  static const _pushChannel = MethodChannel('br.com.felipearaujo.diarias/push');

  static bool _ready = false;

  /// True once Firebase initialised successfully. The rest of the app can use
  /// this to skip analytics calls rather than guard each one.
  static bool get isReady => _ready;

  static FirebaseAnalytics? _analytics;
  static FirebaseAnalytics? get analytics => _analytics;

  /// Initialises Firebase and installs the crash handlers.
  ///
  /// Call inside the same zone as `runApp`, after
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _ready = true;
    } catch (e) {
      // Missing config, no network at first launch, an unsupported platform —
      // none of it should stop the app.
      debugPrint('Firebase.initializeApp failed: $e');
      return;
    }

    _installCrashHandlers();
    _analytics = FirebaseAnalytics.instance;
  }

  static void _installCrashHandlers() {
    try {
      final crashlytics = FirebaseCrashlytics.instance;

      // Debug builds would otherwise fill the dashboard with crashes from
      // code being actively edited.
      unawaited(crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode));

      // Framework errors (build/layout/paint).
      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        previousOnError?.call(details);
        crashlytics.recordFlutterFatalError(details);
      };

      // Errors escaping the framework, e.g. an unawaited future that throws.
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      debugPrint('Crashlytics setup failed: $e');
    }
  }

  /// Ties crash reports and analytics to the signed-in account.
  ///
  /// Only the username — never the token, and never anything about how much
  /// anyone is paid.
  static Future<void> setUser(String? username) async {
    if (!_ready) return;
    try {
      await FirebaseCrashlytics.instance.setUserIdentifier(username ?? '');
      await _analytics?.setUserId(id: username);
    } catch (e) {
      debugPrint('Firebase setUser failed: $e');
    }
  }

  /// Registers for push and returns the identifier accepted by FCM.
  ///
  /// Android's current native SDK uses the Firebase Installation ID (FID).
  /// FlutterFire does not expose that registration API yet, so the Android
  /// host bridges it through [_pushChannel]. Other platforms keep using their
  /// registration token until their client path is migrated too.
  static Future<String?> messagingIdentifier() async {
    if (!_ready) return null;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        return await _pushChannel.invokeMethod<String>('registerInstallation');
      }
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Firebase push registration failed: $e');
      return null;
    }
  }

  /// Emits replacement tokens issued by FCM while the app is alive.
  ///
  /// Android FIDs are refreshed by the native SDK and re-uploaded on launch.
  /// FlutterFire does not expose the native onRegistered callback yet.
  static Stream<String> get messagingTokenRefreshes =>
      _ready && (kIsWeb || defaultTargetPlatform != TargetPlatform.android)
      ? FirebaseMessaging.instance.onTokenRefresh
      : const Stream.empty();

  /// Asks for push permission. Call it from a screen where the user has just
  /// asked for something that needs it.
  static Future<bool> requestPushPermission() async {
    if (!_ready) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('FirebaseMessaging.requestPermission failed: $e');
      return false;
    }
  }
}
