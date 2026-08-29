import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../firebase/firebase_setup.dart';

/// Turns the household's push reminders on and off for this device.
///
/// The reminders themselves are decided by the server, not here: only it knows
/// whether today was already recorded or whether last month is still open, and
/// a reminder that nags about something already done is worse than none.
///
/// This class does the three things the phone must contribute: ask permission,
/// create the Android channel the pushes are tagged with, and tell the API
/// which device to reach.
class ReminderService {
  ReminderService({required this.api, FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final ApiClient api;
  final FlutterLocalNotificationsPlugin _plugin;

  static const _enabledKey = 'diarias.reminder_enabled';
  static const _identifierKey = 'diarias.reminder_identifier';

  /// Must match the `channel_id` the server sets on every push, or Android
  /// silently drops the notification into a default channel the user cannot
  /// tune separately.
  static const channelId = 'fechamento';

  bool _ready = false;
  String? _identifier;
  StreamSubscription<String>? _tokenRefreshSubscription;

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Asked for when the user turns reminders on, not at launch: a
          // permission prompt before anyone has seen the app gets denied.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    // Created up front so the first push has somewhere to land.
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              channelId,
              'Lembretes de fechamento',
              description: 'Avisos para anotar a diária e para fechar o mês.',
              importance: Importance.defaultImportance,
            ),
          );
    } catch (e) {
      debugPrint('createNotificationChannel failed: $e');
    }
    _ready = true;
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// Turns reminders on or off for this device.
  ///
  /// Returns whether they ended up on — the OS can refuse permission, and the
  /// server can be unreachable.
  Future<bool> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();

    if (!enabled) {
      await _unregister();
      await prefs.setBool(_enabledKey, false);
      return false;
    }

    await _ensureReady();
    if (!await FirebaseSetup.requestPushPermission()) {
      await prefs.setBool(_enabledKey, false);
      return false;
    }
    if (!await _register()) {
      await prefs.setBool(_enabledKey, false);
      return false;
    }

    await prefs.setBool(_enabledKey, true);
    _listenForTokenRefresh();
    return true;
  }

  /// Re-registers on launch, so a token/FID changed while the app was closed
  /// does not silently stop the reminders.
  Future<void> refresh() async {
    if (!await isEnabled()) return;
    await _ensureReady();
    if (await _register()) _listenForTokenRefresh();
  }

  Future<bool> _register() async {
    final identifier = await FirebaseSetup.messagingIdentifier();
    if (identifier == null || identifier.isEmpty) return false;
    return _registerIdentifier(identifier);
  }

  Future<bool> _registerIdentifier(String identifier) async {
    try {
      await api.registerDevice(token: identifier, platform: _platform);
      _identifier = identifier;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_identifierKey, identifier);
      return true;
    } on ApiException catch (e) {
      debugPrint('registerDevice failed: $e');
      return false;
    }
  }

  void _listenForTokenRefresh() {
    _tokenRefreshSubscription ??= FirebaseSetup.messagingTokenRefreshes.listen(
      (token) async {
        if (token.isEmpty || !await isEnabled()) return;
        await _registerIdentifier(token);
      },
      onError: (Object error) {
        debugPrint('FCM token refresh failed: $error');
      },
    );
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
  }

  Future<void> _unregister() async {
    final prefs = await SharedPreferences.getInstance();
    final identifier = _identifier ?? prefs.getString(_identifierKey);
    if (identifier == null || identifier.isEmpty) return;
    try {
      await api.unregisterDevice(identifier);
      _identifier = null;
      await prefs.remove(_identifierKey);
    } on ApiException catch (e) {
      // Keep the identifier persisted. If the user enables and disables the
      // feature again, removal from the server can be retried.
      debugPrint('unregisterDevice failed: $e');
    }
  }

  static String get _platform => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android-fid',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    _ => 'outro',
  };
}
