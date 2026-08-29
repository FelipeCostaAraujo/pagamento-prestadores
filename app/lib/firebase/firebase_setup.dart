import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Firebase wiring, kept in one place and deliberately optional.
///
/// Everything here is best-effort: a household app that cannot reach Google
/// must still open and let someone mark a day. Nothing in this file is allowed
/// to throw into startup.
abstract final class FirebaseSetup {
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

  /// Registers for push and returns the device token.
  ///
  /// Nothing consumes this yet: sending a push needs the backend to store
  /// tokens and hold a service-account credential. The permission request is
  /// deliberately not made here — asking at launch, before the user has seen
  /// what the app does, is how you get denied.
  static Future<String?> messagingToken() async {
    if (!_ready) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('FirebaseMessaging.getToken failed: $e');
      return null;
    }
  }

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
