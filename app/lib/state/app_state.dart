import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/models.dart';

enum AppTab { calendar, closing, people }

/// Which week day the calendar grid starts on — the design exposes this as a
/// prototype knob (`weekStart`).
enum WeekStart { sunday, monday }

/// Single source of truth for the app.
///
/// The backend owns the data; this class holds the currently visible month, the
/// prestadora list and the derived closing, and it reloads from the API after
/// every mutation so what is on screen always matches what is stored.
class AppState extends ChangeNotifier {
  AppState({required this.api, DateTime? today})
    : _today = dayOnly(today ?? DateTime.now()) {
    _year = _today.year;
    _month = _today.month;
  }

  final ApiClient api;
  final DateTime _today;

  DateTime get today => _today;

  // -------------------------------------------------------------- view state --

  AppTab _tab = AppTab.calendar;
  AppTab get tab => _tab;

  late int _year;
  late int _month;
  int get year => _year;
  int get month => _month;

  WeekStart _weekStart = WeekStart.sunday;
  WeekStart get weekStart => _weekStart;

  /// Show each day's total inside the calendar cell (design knob
  /// `showDayValues`). Off by default: the dots already say who worked, and the
  /// numbers crowd the grid.
  bool _showDayValues = false;
  bool get showDayValues => _showDayValues;

  // -------------------------------------------------------------- data state --

  List<Provider> _providers = const [];
  List<Provider> get providers => _providers;

  MonthClosing _closing = MonthClosing.empty(0, 0);
  MonthClosing get closing => _closing;

  /// Worked days for the visible month, keyed by `YYYY-MM-DD`.
  Map<String, List<WorkEntry>> _entriesByDay = const {};

  bool _loading = false;
  bool get loading => _loading;

  /// True only for the very first load, so later refreshes don't blank the
  /// screen out from under the user.
  bool _initialLoadDone = false;
  bool get initialLoadDone => _initialLoadDone;

  String? _error;
  String? get error => _error;

  String? _toast;
  String? get toast => _toast;

  // ---------------------------------------------------------------- loading --

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // The three calls are independent; running them together keeps the
      // month switch to a single round-trip's latency.
      final results = await Future.wait([
        api.listProviders(),
        api.monthClosing(year: _year, month: _month),
        api.listEntries(year: _year, month: _month),
      ]);
      _providers = results[0] as List<Provider>;
      _closing = results[1] as MonthClosing;
      _entriesByDay = _groupByDay(results[2] as List<WorkEntry>);
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      _initialLoadDone = true;
      notifyListeners();
    }
  }

  static Map<String, List<WorkEntry>> _groupByDay(List<WorkEntry> entries) {
    final map = <String, List<WorkEntry>>{};
    for (final entry in entries) {
      map.putIfAbsent(dateKey(entry.date), () => []).add(entry);
    }
    return map;
  }

  /// Runs [action], surfacing any API error as a toast and refreshing on
  /// success. Mutations are few and cheap, so a full reload is simpler — and
  /// less prone to drift — than patching local state.
  Future<void> _mutate(
    Future<void> Function() action, {
    String? successToast,
  }) async {
    try {
      await action();
      await load();
      if (successToast != null) showToast(successToast);
    } on ApiException catch (e) {
      showToast(e.message);
    }
  }

  // -------------------------------------------------------------- navigation --

  void setTab(AppTab tab) {
    if (_tab == tab) return;
    _tab = tab;
    notifyListeners();
  }

  void setWeekStart(WeekStart value) {
    if (_weekStart == value) return;
    _weekStart = value;
    notifyListeners();
  }

  void setShowDayValues(bool value) {
    if (_showDayValues == value) return;
    _showDayValues = value;
    notifyListeners();
  }

  /// Moves the visible month by [delta], rolling the year over as needed.
  Future<void> shiftMonth(int delta) async {
    var month = _month + delta;
    var year = _year;
    while (month < 1) {
      month += 12;
      year--;
    }
    while (month > 12) {
      month -= 12;
      year++;
    }
    _month = month;
    _year = year;
    // Clear the old month's days so the grid can't briefly show September's
    // entries under August's numbers.
    _entriesByDay = const {};
    _closing = MonthClosing.empty(year, month);
    notifyListeners();
    await load();
  }

  // ----------------------------------------------------------------- queries --

  List<WorkEntry> entriesOn(DateTime date) =>
      _entriesByDay[dateKey(date)] ?? const [];

  WorkEntry? entryFor(String providerId, DateTime date) {
    for (final entry in entriesOn(date)) {
      if (entry.providerId == providerId) return entry;
    }
    return null;
  }

  int totalOn(DateTime date) =>
      entriesOn(date).fold(0, (sum, e) => sum + e.valueCents);

  Provider? providerById(String id) {
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// How many days each prestadora worked this month, keyed by provider id.
  Map<String, int> get dayCountByProvider {
    final counts = <String, int>{};
    for (final closing in _closing.providers) {
      counts[closing.provider.id] = closing.entryCount;
    }
    return counts;
  }

  /// The four most recent entries in the visible month, newest first — the
  /// calendar's "Últimos lançamentos" list.
  List<WorkEntry> get recentEntries {
    final all = _entriesByDay.values.expand((e) => e).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return all.take(4).toList(growable: false);
  }

  // --------------------------------------------------------------- mutations --

  /// Marks or unmarks [date] for a prestadora. Marking adopts her current
  /// default rate; the value can then be changed for that day alone.
  Future<void> toggleEntry(String providerId, DateTime date) {
    final existing = entryFor(providerId, date);
    return _mutate(() async {
      if (existing != null) {
        await api.deleteEntry(providerId: providerId, date: date);
      } else {
        await api.upsertEntry(providerId: providerId, date: date);
      }
    });
  }

  /// Overrides the value of a single day without touching the default rate.
  Future<void> setEntryValue(
    String providerId,
    DateTime date,
    int valueCents,
  ) {
    return _mutate(
      () => api.upsertEntry(
        providerId: providerId,
        date: date,
        valueCents: valueCents,
      ),
    );
  }

  Future<void> addProvider() =>
      _mutate(() => api.createProvider(defaultRateCents: 17000));

  Future<void> renameProvider(String id, String name) {
    final current = providerById(id);
    if (current != null && current.name == name) return Future.value();
    return _mutate(() => api.updateProvider(id, name: name));
  }

  Future<void> setProviderRate(String id, int rateCents) {
    final current = providerById(id);
    if (current != null && current.defaultRateCents == rateCents) {
      return Future.value();
    }
    return _mutate(() => api.updateProvider(id, defaultRateCents: rateCents));
  }

  Future<void> deleteProvider(String id) {
    final name = providerById(id)?.firstName ?? 'Prestadora';
    return _mutate(
      () => api.deleteProvider(id),
      successToast: '$name foi removida',
    );
  }

  Future<void> setPaid(String providerId, bool paid, {String? toast}) {
    return _mutate(() async {
      if (paid) {
        await api.markPaid(
          year: _year,
          month: _month,
          providerId: providerId,
        );
      } else {
        await api.unmarkPaid(
          year: _year,
          month: _month,
          providerId: providerId,
        );
      }
    }, successToast: toast);
  }

  // ------------------------------------------------------------------ toasts --

  void showToast(String message) {
    _toast = message;
    notifyListeners();
  }

  void clearToast() {
    if (_toast == null) return;
    _toast = null;
    notifyListeners();
  }
}
