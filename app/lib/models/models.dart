/// Wire models for the Diárias API.
///
/// Field names mirror the Go JSON contract exactly so the two sides can be read
/// side by side. All money is integer cents — see [dateKey] for the date
/// convention.
library;

import 'package:flutter/foundation.dart';

/// Formats a date as the API's `YYYY-MM-DD`, which is also the key used for
/// day lookups throughout the app.
String dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// Strips any time component so dates compare and hash by calendar day.
DateTime dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime _parseDate(String value) {
  final parts = value.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// What a marked day means. Mirrors the backend's `kind`.
///
/// An absence is a record, not the lack of one: "ela era esperada e não veio"
/// is different information from a day nobody ever touched.
enum EntryKind {
  full('full'),
  half('half'),
  absence('absence');

  const EntryKind(this.wire);

  /// The value sent to and received from the API.
  final String wire;

  /// Whether the day is owed money.
  bool get billable => this != EntryKind.absence;

  String get label => switch (this) {
    EntryKind.full => 'Integral',
    EntryKind.half => 'Meia',
    EntryKind.absence => 'Falta',
  };

  /// What this kind costs given the prestadora's rate — the same rule the
  /// server applies, so an optimistic update matches what comes back.
  int defaultValue(int rateCents) => switch (this) {
    EntryKind.full => rateCents,
    EntryKind.half => rateCents ~/ 2,
    EntryKind.absence => 0,
  };

  /// Unknown values fall back to a full day rather than throwing: a newer
  /// server must not be able to crash an older app.
  static EntryKind parse(String? value) => EntryKind.values.firstWhere(
    (k) => k.wire == value,
    orElse: () => EntryKind.full,
  );
}

@immutable
class Provider {
  const Provider({
    required this.id,
    required this.name,
    required this.defaultRateCents,
    required this.colorIndex,
    required this.position,
    this.phone = '',
    this.remindWeekdays = const [],
    this.remindAt = '19:00',
  });

  final String id;
  final String name;
  final int defaultRateCents;

  /// As typed. Empty means the closing cannot be sent to her directly.
  final String phone;

  /// Days this person is expected, 0=Sunday..6=Saturday. Empty means no
  /// routine — someone who only comes when called.
  final List<int> remindWeekdays;

  /// Local time to be asked whether the day was recorded, "HH:MM".
  final String remindAt;

  bool get hasSchedule => remindWeekdays.isNotEmpty;

  bool get hasPhone => phone.trim().isNotEmpty;

  /// Digits only, with Brazil's country code, as wa.me expects.
  ///
  /// Returns null when what was typed cannot be a Brazilian mobile number, so
  /// the caller offers copying instead of opening a broken link.
  String? get whatsappNumber {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    // Already carries the country code.
    if (digits.startsWith('55') &&
        (digits.length == 12 || digits.length == 13)) {
      return digits;
    }
    // Local number with area code.
    if (digits.length == 10 || digits.length == 11) return '55$digits';
    return null;
  }

  /// Index into the app's prestadora palette (see `DsPalette`).
  final int colorIndex;
  final int position;

  /// The name to show when the user has not typed one yet.
  String get displayName => name.trim().isEmpty ? 'Sem nome' : name.trim();

  /// First name, for the compact legend chips and WhatsApp copy.
  String get firstName {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Sem nome';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  factory Provider.fromJson(Map<String, dynamic> json) => Provider(
    id: json['id'] as String,
    name: (json['name'] as String?) ?? '',
    defaultRateCents: (json['default_rate_cents'] as num).toInt(),
    colorIndex: (json['color_index'] as num).toInt(),
    position: (json['position'] as num).toInt(),
    phone: (json['phone'] as String?) ?? '',
    remindWeekdays: ((json['remind_weekdays'] as List<dynamic>?) ?? const [])
        .map((d) => (d as num).toInt())
        .toList(growable: false),
    remindAt: (json['remind_at'] as String?) ?? '19:00',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'default_rate_cents': defaultRateCents,
    'color_index': colorIndex,
    'position': position,
    'phone': phone,
    'remind_weekdays': remindWeekdays,
    'remind_at': remindAt,
  };

  Provider copyWith({String? name, int? defaultRateCents, String? phone}) =>
      Provider(
        id: id,
        name: name ?? this.name,
        defaultRateCents: defaultRateCents ?? this.defaultRateCents,
        colorIndex: colorIndex,
        position: position,
        phone: phone ?? this.phone,
        remindWeekdays: remindWeekdays,
        remindAt: remindAt,
      );
}

/// One day a prestadora worked.
@immutable
class WorkEntry {
  const WorkEntry({
    required this.id,
    required this.providerId,
    required this.date,
    required this.valueCents,
    this.kind = EntryKind.full,
  });

  final String id;
  final String providerId;
  final DateTime date;
  final int valueCents;
  final EntryKind kind;

  factory WorkEntry.fromJson(Map<String, dynamic> json) => WorkEntry(
    id: json['id'] as String,
    providerId: json['provider_id'] as String,
    date: _parseDate(json['date'] as String),
    valueCents: (json['value_cents'] as num).toInt(),
    kind: EntryKind.parse(json['kind'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'provider_id': providerId,
    'date': dateKey(date),
    'value_cents': valueCents,
    'kind': kind.wire,
  };
}

@immutable
class ClosingDay {
  const ClosingDay({
    required this.date,
    required this.valueCents,
    this.kind = EntryKind.full,
  });

  final DateTime date;
  final int valueCents;
  final EntryKind kind;

  factory ClosingDay.fromJson(Map<String, dynamic> json) => ClosingDay(
    date: _parseDate(json['date'] as String),
    valueCents: (json['value_cents'] as num).toInt(),
    kind: EntryKind.parse(json['kind'] as String?),
  );

  Map<String, dynamic> toJson() => {
    'date': dateKey(date),
    'value_cents': valueCents,
    'kind': kind.wire,
  };
}

/// A prestadora's month: what she worked and whether it is paid.
@immutable
class ProviderClosing {
  const ProviderClosing({
    required this.provider,
    required this.entryCount,
    required this.totalCents,
    required this.days,
    required this.paid,
    this.halfCount = 0,
    this.absenceCount = 0,
  });

  final Provider provider;

  /// Days actually worked — full and half. Absences are counted separately so
  /// "3 diárias" never quietly includes a no-show.
  final int entryCount;
  final int halfCount;
  final int absenceCount;
  final int totalCents;
  final List<ClosingDay> days;
  final bool paid;

  factory ProviderClosing.fromJson(Map<String, dynamic> json) =>
      ProviderClosing(
        provider: Provider.fromJson(json['provider'] as Map<String, dynamic>),
        entryCount: (json['entry_count'] as num).toInt(),
        halfCount: (json['half_count'] as num?)?.toInt() ?? 0,
        absenceCount: (json['absence_count'] as num?)?.toInt() ?? 0,
        totalCents: (json['total_cents'] as num).toInt(),
        days: ((json['days'] as List<dynamic>?) ?? const [])
            .map((d) => ClosingDay.fromJson(d as Map<String, dynamic>))
            .toList(growable: false),
        paid: (json['paid'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
    'provider': provider.toJson(),
    'entry_count': entryCount,
    'half_count': halfCount,
    'absence_count': absenceCount,
    'total_cents': totalCents,
    'paid': paid,
    'days': days.map((d) => d.toJson()).toList(),
  };
}

/// The Fechamento screen's payload for one month.
@immutable
class MonthClosing {
  const MonthClosing({
    required this.year,
    required this.month,
    required this.providers,
    required this.totalCents,
    required this.outstandingCents,
    required this.workedDays,
  });

  final int year;
  final int month;
  final List<ProviderClosing> providers;
  final int totalCents;

  /// Total still owed — excludes prestadoras already marked as paid. This is
  /// the header's "A pagar".
  final int outstandingCents;
  final int workedDays;

  /// Prestadoras who worked this month and have not been paid yet.
  int get openCount =>
      providers.where((p) => !p.paid && p.entryCount > 0).length;

  factory MonthClosing.fromJson(Map<String, dynamic> json) => MonthClosing(
    year: (json['year'] as num).toInt(),
    month: (json['month'] as num).toInt(),
    providers: ((json['providers'] as List<dynamic>?) ?? const [])
        .map((p) => ProviderClosing.fromJson(p as Map<String, dynamic>))
        .toList(growable: false),
    totalCents: (json['total_cents'] as num).toInt(),
    outstandingCents: (json['outstanding_cents'] as num).toInt(),
    workedDays: (json['worked_days'] as num).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'year': year,
    'month': month,
    'providers': providers.map((p) => p.toJson()).toList(),
    'total_cents': totalCents,
    'outstanding_cents': outstandingCents,
    'worked_days': workedDays,
  };

  static MonthClosing empty(int year, int month) => MonthClosing(
    year: year,
    month: month,
    providers: const [],
    totalCents: 0,
    outstandingCents: 0,
    workedDays: 0,
  );
}
