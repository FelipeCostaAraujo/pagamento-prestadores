import 'package:diarias/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EntryKind', () {
    test('half is worth half the rate, absence nothing', () {
      expect(EntryKind.full.defaultValue(17000), 17000);
      expect(EntryKind.half.defaultValue(17000), 8500);
      expect(EntryKind.absence.defaultValue(17000), 0);
    });

    test('an odd rate halves without gaining a cent', () {
      // Integer division, matching the backend's `rate / 2` in SQL — the two
      // must agree or the optimistic value would flicker on refresh.
      expect(EntryKind.half.defaultValue(17001), 8500);
    });

    test('only an absence is unbillable', () {
      expect(EntryKind.full.billable, isTrue);
      expect(EntryKind.half.billable, isTrue);
      expect(EntryKind.absence.billable, isFalse);
    });

    test('parses the wire values', () {
      expect(EntryKind.parse('full'), EntryKind.full);
      expect(EntryKind.parse('half'), EntryKind.half);
      expect(EntryKind.parse('absence'), EntryKind.absence);
    });

    test('an unknown kind degrades to a full day instead of throwing', () {
      // A newer server must not be able to crash an older app.
      expect(EntryKind.parse('quarter'), EntryKind.full);
      expect(EntryKind.parse(null), EntryKind.full);
    });
  });

  group('wire models', () {
    test('WorkEntry carries the kind', () {
      final entry = WorkEntry.fromJson({
        'id': 'e1',
        'provider_id': 'p1',
        'date': '2026-08-05',
        'value_cents': 8500,
        'kind': 'half',
      });
      expect(entry.kind, EntryKind.half);
      expect(entry.valueCents, 8500);
    });

    test('an entry from before kinds existed reads as a full day', () {
      final entry = WorkEntry.fromJson({
        'id': 'e1',
        'provider_id': 'p1',
        'date': '2026-08-05',
        'value_cents': 17000,
      });
      expect(entry.kind, EntryKind.full);
    });

    test('the closing separates worked days from absences', () {
      final closing = ProviderClosing.fromJson({
        'provider': {
          'id': 'p1',
          'name': 'Marília',
          'default_rate_cents': 17000,
          'color_index': 0,
          'position': 0,
        },
        'entry_count': 2,
        'half_count': 1,
        'absence_count': 1,
        'total_cents': 25500,
        'paid': false,
        'days': [
          {'date': '2026-08-03', 'value_cents': 17000, 'kind': 'full'},
          {'date': '2026-08-04', 'value_cents': 8500, 'kind': 'half'},
          {'date': '2026-08-05', 'value_cents': 0, 'kind': 'absence'},
        ],
      });

      expect(closing.entryCount, 2, reason: 'a falta não é diária');
      expect(closing.halfCount, 1);
      expect(closing.absenceCount, 1);
      expect(closing.totalCents, 25500);
      // The absence still shows on the card; it just is not owed.
      expect(closing.days, hasLength(3));
      expect(closing.days.last.kind, EntryKind.absence);
      expect(closing.days.last.valueCents, 0);
    });
  });
}
