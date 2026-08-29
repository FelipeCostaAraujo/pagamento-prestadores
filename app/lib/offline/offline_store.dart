import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// A write made while the phone had no connection, waiting to be replayed.
///
/// Only day-level edits are queued. Creating a prestadora is not: it needs the
/// server-assigned id before anything else can reference her, and inventing one
/// locally would mean reconciling identities later for a button that is pressed
/// twice a year.
@immutable
class PendingWrite {
  const PendingWrite({
    required this.op,
    required this.providerId,
    required this.date,
    this.kind = EntryKind.full,
    this.valueCents,
  });

  /// 'upsert' or 'delete'.
  final String op;
  final String providerId;
  final DateTime date;
  final EntryKind kind;
  final int? valueCents;

  /// Two writes to the same prestadora on the same day collapse: the later one
  /// wins, which is what the API's upsert does anyway.
  String get slot => '$providerId:${dateKey(date)}';

  Map<String, dynamic> toJson() => {
    'op': op,
    'provider_id': providerId,
    'date': dateKey(date),
    'kind': kind.wire,
    if (valueCents != null) 'value_cents': valueCents,
  };

  factory PendingWrite.fromJson(Map<String, dynamic> json) => PendingWrite(
    op: json['op'] as String,
    providerId: json['provider_id'] as String,
    date: DateTime.parse(json['date'] as String),
    kind: EntryKind.parse(json['kind'] as String?),
    valueCents: (json['value_cents'] as num?)?.toInt(),
  );
}

/// What the app remembers when it cannot reach the server.
@immutable
class CachedMonth {
  const CachedMonth({
    required this.providers,
    required this.entries,
    required this.closing,
    required this.savedAt,
  });

  final List<Provider> providers;
  final List<WorkEntry> entries;
  final MonthClosing closing;
  final DateTime savedAt;
}

/// Read cache and write queue, persisted so both survive the app being killed.
///
/// Deliberately in SharedPreferences rather than a database: this is a few
/// dozen rows per month, and a schema to migrate would cost more than it saves.
class OfflineStore {
  static const _cachePrefix = 'diarias.cache.';
  static const _queueKey = 'diarias.queue';

  static String _cacheKey(int year, int month) =>
      '$_cachePrefix$year-${month.toString().padLeft(2, '0')}';

  /// Stores a month exactly as the server returned it.
  Future<void> saveMonth({
    required int year,
    required int month,
    required List<Provider> providers,
    required List<WorkEntry> entries,
    required MonthClosing closing,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey(year, month),
        jsonEncode({
          'saved_at': DateTime.now().toIso8601String(),
          'providers': providers.map((p) => p.toJson()).toList(),
          'entries': entries.map((e) => e.toJson()).toList(),
          'closing': closing.toJson(),
        }),
      );
    } catch (e) {
      // A cache that cannot be written is a missing convenience, not an error.
      debugPrint('OfflineStore.saveMonth failed: $e');
    }
  }

  Future<CachedMonth?> readMonth(int year, int month) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(year, month));
      if (raw == null) return null;

      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CachedMonth(
        providers: (json['providers'] as List<dynamic>)
            .map((p) => Provider.fromJson(p as Map<String, dynamic>))
            .toList(),
        entries: (json['entries'] as List<dynamic>)
            .map((e) => WorkEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        closing: MonthClosing.fromJson(json['closing'] as Map<String, dynamic>),
        savedAt: DateTime.parse(json['saved_at'] as String),
      );
    } catch (e) {
      // Corrupt or written by an older version — treat as no cache at all.
      debugPrint('OfflineStore.readMonth failed: $e');
      return null;
    }
  }

  Future<List<PendingWrite>> readQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_queueKey);
      if (raw == null) return const [];
      return (jsonDecode(raw) as List<dynamic>)
          .map((w) => PendingWrite.fromJson(w as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('OfflineStore.readQueue failed: $e');
      return const [];
    }
  }

  /// Appends a write, replacing any earlier one for the same day.
  ///
  /// Without the collapse, toggling a day on and off five times offline would
  /// replay as five requests instead of the one that reflects what the user
  /// actually left on screen.
  Future<List<PendingWrite>> enqueue(PendingWrite write) async {
    final queue = [...await readQueue()]
      ..removeWhere((w) => w.slot == write.slot)
      ..add(write);
    await _writeQueue(queue);
    return queue;
  }

  Future<void> _writeQueue(List<PendingWrite> queue) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (queue.isEmpty) {
        await prefs.remove(_queueKey);
        return;
      }
      await prefs.setString(
        _queueKey,
        jsonEncode(queue.map((w) => w.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('OfflineStore._writeQueue failed: $e');
    }
  }

  Future<void> clearQueue() => _writeQueue(const []);

  /// Drops the writes that were replayed, keeping any queued meanwhile.
  Future<void> removeReplayed(Iterable<PendingWrite> done) async {
    final slots = done.map((w) => w.slot).toSet();
    final remaining = (await readQueue())
        .where((w) => !slots.contains(w.slot))
        .toList();
    await _writeQueue(remaining);
  }
}
