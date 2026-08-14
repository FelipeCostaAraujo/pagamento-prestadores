import 'package:diarias/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dateKey', () {
    test('zero-pads to the API format', () {
      expect(dateKey(DateTime(2026, 8, 3)), '2026-08-03');
      expect(dateKey(DateTime(2026, 12, 25)), '2026-12-25');
    });

    test('ignores any time component', () {
      expect(dateKey(DateTime(2026, 8, 3, 23, 59)), '2026-08-03');
    });
  });

  group('Provider', () {
    test('parses the API payload', () {
      final provider = Provider.fromJson({
        'id': 'abc',
        'name': 'Marina Souza',
        'default_rate_cents': 18000,
        'color_index': 0,
        'position': 0,
        'created_at': '2026-08-01T00:00:00Z',
        'updated_at': '2026-08-01T00:00:00Z',
      });

      expect(provider.name, 'Marina Souza');
      expect(provider.defaultRateCents, 18000);
      expect(provider.firstName, 'Marina');
      expect(provider.displayName, 'Marina Souza');
    });

    test('falls back to a placeholder when unnamed', () {
      final provider = Provider.fromJson({
        'id': 'abc',
        'name': '',
        'default_rate_cents': 0,
        'color_index': 1,
        'position': 1,
      });

      expect(provider.displayName, 'Sem nome');
      expect(provider.firstName, 'Sem nome');
    });
  });

  group('MonthClosing', () {
    Map<String, dynamic> providerJson(String id, String name) => {
      'id': id,
      'name': name,
      'default_rate_cents': 18000,
      'color_index': 0,
      'position': 0,
    };

    test('parses providers, totals and days', () {
      final closing = MonthClosing.fromJson({
        'year': 2026,
        'month': 8,
        'total_cents': 33000,
        'outstanding_cents': 15000,
        'worked_days': 2,
        'providers': [
          {
            'provider': providerJson('p1', 'Marina Souza'),
            'entry_count': 1,
            'total_cents': 18000,
            'paid': true,
            'days': [
              {'date': '2026-08-03', 'value_cents': 18000},
            ],
          },
          {
            'provider': providerJson('p2', 'Cleide Ramos'),
            'entry_count': 1,
            'total_cents': 15000,
            'paid': false,
            'days': [
              {'date': '2026-08-05', 'value_cents': 15000},
            ],
          },
        ],
      });

      expect(closing.providers, hasLength(2));
      expect(closing.totalCents, 33000);
      expect(closing.outstandingCents, 15000);
      expect(closing.providers.first.days.single.date, DateTime(2026, 8, 3));
      // Only the unpaid prestadora counts as open.
      expect(closing.openCount, 1);
    });

    test('a prestadora with no days is not counted as open', () {
      final closing = MonthClosing.fromJson({
        'year': 2026,
        'month': 8,
        'total_cents': 0,
        'outstanding_cents': 0,
        'worked_days': 0,
        'providers': [
          {
            'provider': providerJson('p1', 'Marina Souza'),
            'entry_count': 0,
            'total_cents': 0,
            'paid': false,
            'days': <Map<String, dynamic>>[],
          },
        ],
      });

      expect(closing.openCount, 0);
    });
  });
}
