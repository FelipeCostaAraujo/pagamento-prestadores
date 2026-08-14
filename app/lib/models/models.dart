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

@immutable
class Provider {
  const Provider({
    required this.id,
    required this.name,
    required this.defaultRateCents,
    required this.colorIndex,
    required this.position,
  });

  final String id;
  final String name;
  final int defaultRateCents;

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
  );

  Provider copyWith({String? name, int? defaultRateCents}) => Provider(
    id: id,
    name: name ?? this.name,
    defaultRateCents: defaultRateCents ?? this.defaultRateCents,
    colorIndex: colorIndex,
    position: position,
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
  });

  final String id;
  final String providerId;
  final DateTime date;
  final int valueCents;

  factory WorkEntry.fromJson(Map<String, dynamic> json) => WorkEntry(
    id: json['id'] as String,
    providerId: json['provider_id'] as String,
    date: _parseDate(json['date'] as String),
    valueCents: (json['value_cents'] as num).toInt(),
  );
}

@immutable
class ClosingDay {
  const ClosingDay({required this.date, required this.valueCents});

  final DateTime date;
  final int valueCents;

  factory ClosingDay.fromJson(Map<String, dynamic> json) => ClosingDay(
    date: _parseDate(json['date'] as String),
    valueCents: (json['value_cents'] as num).toInt(),
  );
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
  });

  final Provider provider;
  final int entryCount;
  final int totalCents;
  final List<ClosingDay> days;
  final bool paid;

  factory ProviderClosing.fromJson(Map<String, dynamic> json) =>
      ProviderClosing(
        provider: Provider.fromJson(json['provider'] as Map<String, dynamic>),
        entryCount: (json['entry_count'] as num).toInt(),
        totalCents: (json['total_cents'] as num).toInt(),
        days: ((json['days'] as List<dynamic>?) ?? const [])
            .map((d) => ClosingDay.fromJson(d as Map<String, dynamic>))
            .toList(growable: false),
        paid: (json['paid'] as bool?) ?? false,
      );
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

  static MonthClosing empty(int year, int month) => MonthClosing(
    year: year,
    month: month,
    providers: const [],
    totalCents: 0,
    outstandingCents: 0,
    workedDays: 0,
  );
}
