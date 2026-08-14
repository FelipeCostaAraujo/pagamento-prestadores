import 'package:diarias/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatMoney', () {
    test('formats cents as Brazilian currency', () {
      expect(formatMoney(0), r'R$ 0,00');
      expect(formatMoney(18000), r'R$ 180,00');
      expect(formatMoney(15050), r'R$ 150,50');
      expect(formatMoney(5), r'R$ 0,05');
    });

    test('groups thousands with dots', () {
      expect(formatMoney(180000), r'R$ 1.800,00');
      expect(formatMoney(123456789), r'R$ 1.234.567,89');
    });

    test('keeps the sign in front of the amount', () {
      expect(formatMoney(-18000), r'R$ -180,00');
    });
  });

  group('formatCompactAmount', () {
    test('drops zero cents', () {
      expect(formatCompactAmount(18000), '180');
      expect(formatCompactAmount(180000), '1.800');
    });

    test('keeps non-zero cents', () {
      expect(formatCompactAmount(15050), '150,50');
    });
  });

  group('parseCents', () {
    test('accepts Brazilian formatting', () {
      expect(parseCents('180'), 18000);
      expect(parseCents('180,50'), 18050);
      expect(parseCents('1.800,00'), 180000);
      expect(parseCents(r'R$ 1.800,00'), 180000);
    });

    test('accepts dot-decimal input', () {
      expect(parseCents('180.50'), 18050);
      expect(parseCents('1,800.00'), 180000);
    });

    test('rounds rather than truncating', () {
      expect(parseCents('180,999'), 18100);
      expect(parseCents('0,005'), 1);
    });

    test('returns null when there is no number', () {
      expect(parseCents(''), isNull);
      expect(parseCents('   '), isNull);
      expect(parseCents('abc'), isNull);
      expect(parseCents(r'R$'), isNull);
      expect(parseCents('-'), isNull);
    });

    test('round-trips through formatAmount', () {
      for (final cents in [0, 5, 18000, 15050, 180000, 123456789]) {
        expect(parseCents(formatAmount(cents)), cents, reason: '$cents');
      }
    });
  });

  group('date labels', () {
    test('month and weekday names are pt-BR', () {
      expect(monthName(3), 'março');
      expect(monthLabel(2026, 8), 'Agosto de 2026');
      // 3 August 2026 is a Monday.
      expect(weekdayName(DateTime(2026, 8, 3)), 'segunda');
      // 2 August 2026 is a Sunday — index 0 in weekdayNames.
      expect(weekdayName(DateTime(2026, 8, 2)), 'domingo');
    });

    test('formats the sheet and chip labels', () {
      final date = DateTime(2026, 8, 3);
      expect(longDayLabel(date), 'Segunda, 3 de agosto');
      expect(shortDayLabel(date), '03/08');
      expect(recentDateLabel(date), 'segunda, 3 de agosto');
    });
  });
}
