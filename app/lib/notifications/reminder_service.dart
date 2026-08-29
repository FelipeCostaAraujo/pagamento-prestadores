import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../format.dart';

/// Schedules the end-of-month reminder to close and pay.
///
/// Local scheduling on purpose: the reminder is a fixed date the phone already
/// knows, so it needs no server, no push credentials and no Firebase — and it
/// fires even with the app closed and no network.
class ReminderService {
  ReminderService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _enabledKey = 'diarias.reminder_enabled';
  static const _channelId = 'fechamento';

  /// How many months ahead to schedule. The OS keeps pending alarms, so a
  /// year covers a long stretch of the app never being opened; every launch
  /// tops them back up.
  static const _monthsAhead = 12;

  /// Reminder time on the last day of the month.
  static const _hour = 19;

  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    // The plugin schedules in a named zone, so the database has to be loaded
    // before any TZDateTime is built.
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Asked for explicitly in [requestPermission] instead, so the prompt
          // appears when the user turns the reminder on rather than at launch.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// Turns the reminder on or off, asking for permission the first time.
  ///
  /// Returns whether it ended up enabled — the OS can refuse.
  Future<bool> setEnabled(bool enabled) async {
    await _ensureReady();
    final prefs = await SharedPreferences.getInstance();

    if (!enabled) {
      await _plugin.cancelAll();
      await prefs.setBool(_enabledKey, false);
      return false;
    }

    if (!await requestPermission()) {
      await prefs.setBool(_enabledKey, false);
      return false;
    }

    await prefs.setBool(_enabledKey, true);
    await scheduleAll();
    return true;
  }

  Future<bool> requestPermission() async {
    await _ensureReady();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }

      final apple = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (apple != null) {
        return await apple.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      // Desktop has no permission gate.
      return true;
    } catch (e) {
      debugPrint('ReminderService.requestPermission failed: $e');
      return false;
    }
  }

  /// Re-schedules the next year of reminders, replacing whatever was pending.
  ///
  /// Safe to call on every launch: ids are derived from year and month, so a
  /// repeat schedule overwrites rather than duplicates.
  Future<void> scheduleAll() async {
    await _ensureReady();
    if (!await isEnabled()) return;

    try {
      await _plugin.cancelAll();
      final now = tz.TZDateTime.now(tz.local);

      for (var i = 0; i < _monthsAhead; i++) {
        final month = DateTime(now.year, now.month + i);
        final when = lastDayOfMonth(month);
        // Skip a date that has already passed this month.
        if (!when.isAfter(now)) continue;

        await _plugin.zonedSchedule(
          id: month.year * 100 + month.month,
          scheduledDate: when,
          title: 'Fechamento de ${monthName(month.month)}',
          body: 'Confira as diárias do mês e pague quem trabalhou.',
          // Inexact on purpose: an exact alarm needs SCHEDULE_EXACT_ALARM,
          // which Android treats as a privileged permission. A reminder that
          // may land a few minutes late is worth not asking for that.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              'Fechamento do mês',
              channelDescription:
                  'Lembrete no último dia do mês para fechar e pagar.',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      }
    } catch (e) {
      // A reminder that fails to schedule must never stop the app from opening.
      debugPrint('ReminderService.scheduleAll failed: $e');
    }
  }

  /// The last day of [month] at the reminder hour, in the device's zone.
  ///
  /// Day zero of the next month is the last day of this one, which gets
  /// February and leap years right with no special cases.
  static tz.TZDateTime lastDayOfMonth(DateTime month) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    return tz.TZDateTime(tz.local, month.year, month.month, lastDay, _hour);
  }
}
