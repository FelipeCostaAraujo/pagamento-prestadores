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

  /// Actions currently in flight, by key.
  ///
  /// Two jobs: it drives the per-button spinners, and it makes a second tap on
  /// an action that is already running a no-op. Without that guard a slow
  /// network turns an impatient double-tap on "+ Nova prestadora" into two
  /// prestadoras.
  final Set<String> _pending = <String>{};

  bool isPending(String key) => _pending.contains(key);

  /// True while any write is in flight.
  bool get isSaving => _pending.isNotEmpty;

  static const addProviderKey = 'provider:add';

  static String entryKey(String providerId, DateTime date) =>
      'entry:$providerId:${dateKey(date)}';

  static String payKey(String providerId) => 'pay:$providerId';

  static String providerKey(String id) => 'provider:$id';

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

  /// Drops everything loaded for the previous session.
  ///
  /// Called on sign-out so the next account cannot briefly see the last one's
  /// prestadoras and totals while its own load is in flight.
  void reset() {
    _providers = const [];
    _closing = MonthClosing.empty(_year, _month);
    _entriesByDay = const {};
    _initialLoadDone = false;
    _loading = false;
    _error = null;
    _toast = null;
    _tab = AppTab.calendar;
    _year = _today.year;
    _month = _today.month;
    notifyListeners();
  }

  static Map<String, List<WorkEntry>> _groupByDay(List<WorkEntry> entries) {
    final map = <String, List<WorkEntry>>{};
    for (final entry in entries) {
      map.putIfAbsent(dateKey(entry.date), () => []).add(entry);
    }
    return map;
  }

  /// Refreshes only what a day change can affect: the month's entries and its
  /// closing. The prestadora list is untouched by marking a day, so re-fetching
  /// it would just add latency to the hot path.
  Future<void> _refreshMonth() async {
    final results = await Future.wait([
      api.monthClosing(year: _year, month: _month),
      api.listEntries(year: _year, month: _month),
    ]);
    _closing = results[0] as MonthClosing;
    _entriesByDay = _groupByDay(results[1] as List<WorkEntry>);
  }

  /// Runs [action] under the key [key], which must be unique per logical
  /// action.
  ///
  /// A repeat call while the same key is in flight is dropped — that is the
  /// double-tap guard. [rollback] undoes an optimistic local change when the
  /// server rejects it.
  Future<void> _mutate(
    String key,
    Future<void> Function() action, {
    String? successToast,
    Future<void> Function()? refresh,
    VoidCallback? rollback,
  }) async {
    if (!_pending.add(key)) return;
    notifyListeners();

    try {
      await action();
      await (refresh ?? load)();
      if (successToast != null) showToast(successToast);
    } on ApiException catch (e) {
      rollback?.call();
      showToast(e.message);
    } finally {
      _pending.remove(key);
      notifyListeners();
    }
  }

  /// Replaces (or clears, when [entry] is null) a prestadora's entry on one
  /// day, building a new map so a snapshot taken beforehand stays valid as a
  /// rollback.
  void _setEntryLocally(String providerId, DateTime date, WorkEntry? entry) {
    final key = dateKey(date);
    final next = Map<String, List<WorkEntry>>.from(_entriesByDay);
    final list = [...?next[key]]
      ..removeWhere((e) => e.providerId == providerId);
    if (entry != null) list.add(entry);
    if (list.isEmpty) {
      next.remove(key);
    } else {
      next[key] = list;
    }
    _entriesByDay = next;
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
  ///
  /// The change is applied locally first so the checkbox answers the tap rather
  /// than the round trip — over the internet that is the difference between
  /// instant and about a second. The server call then confirms it, and a
  /// failure rolls the local change back.
  Future<void> toggleEntry(String providerId, DateTime date) {
    final key = entryKey(providerId, date);
    if (isPending(key)) return Future.value();

    final existing = entryFor(providerId, date);
    final snapshot = _entriesByDay;

    _setEntryLocally(
      providerId,
      date,
      existing != null
          ? null
          : WorkEntry(
              // Replaced by the server's row on the refresh that follows.
              id: 'pendente:$providerId:${dateKey(date)}',
              providerId: providerId,
              date: dayOnly(date),
              valueCents: providerById(providerId)?.defaultRateCents ?? 0,
            ),
    );
    notifyListeners();

    return _mutate(
      key,
      () async {
        if (existing != null) {
          await api.deleteEntry(providerId: providerId, date: date);
        } else {
          await api.upsertEntry(providerId: providerId, date: date);
        }
      },
      refresh: _refreshMonth,
      rollback: () => _entriesByDay = snapshot,
    );
  }

  /// Overrides the value of a single day without touching the default rate.
  Future<void> setEntryValue(String providerId, DateTime date, int valueCents) {
    final key = entryKey(providerId, date);
    if (isPending(key)) return Future.value();

    final existing = entryFor(providerId, date);
    final snapshot = _entriesByDay;

    if (existing != null) {
      _setEntryLocally(
        providerId,
        date,
        WorkEntry(
          id: existing.id,
          providerId: providerId,
          date: existing.date,
          valueCents: valueCents,
        ),
      );
      notifyListeners();
    }

    return _mutate(
      key,
      () => api.upsertEntry(
        providerId: providerId,
        date: date,
        valueCents: valueCents,
      ),
      refresh: _refreshMonth,
      rollback: () => _entriesByDay = snapshot,
    );
  }

  Future<void> addProvider() => _mutate(
    addProviderKey,
    () => api.createProvider(defaultRateCents: 17000),
  );

  Future<void> renameProvider(String id, String name) {
    final current = providerById(id);
    if (current != null && current.name == name) return Future.value();
    return _mutate(providerKey(id), () => api.updateProvider(id, name: name));
  }

  Future<void> setProviderRate(String id, int rateCents) {
    final current = providerById(id);
    if (current != null && current.defaultRateCents == rateCents) {
      return Future.value();
    }
    return _mutate(
      providerKey(id),
      () => api.updateProvider(id, defaultRateCents: rateCents),
    );
  }

  Future<void> deleteProvider(String id) {
    final name = providerById(id)?.firstName ?? 'Prestadora';
    return _mutate(
      providerKey(id),
      () => api.deleteProvider(id),
      successToast: '$name foi removida',
    );
  }

  Future<void> setPaid(String providerId, bool paid, {String? toast}) {
    return _mutate(
      payKey(providerId),
      () async {
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
      },
      successToast: toast,
      refresh: _refreshMonth,
    );
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
