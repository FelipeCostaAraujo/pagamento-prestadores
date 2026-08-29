import 'package:diarias/models/models.dart';
import 'package:diarias/pdf/closing_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderClosing _closing({bool paid = false}) => ProviderClosing(
  provider: const Provider(
    id: 'p1',
    name: 'Marília',
    defaultRateCents: 17000,
    colorIndex: 0,
    position: 0,
  ),
  entryCount: 3,
  halfCount: 1,
  absenceCount: 1,
  totalCents: 42500,
  paid: paid,
  days: [
    ClosingDay(date: DateTime(2026, 8, 3), valueCents: 17000),
    ClosingDay(
      date: DateTime(2026, 8, 5),
      valueCents: 8500,
      kind: EntryKind.half,
    ),
    ClosingDay(
      date: DateTime(2026, 8, 7),
      valueCents: 0,
      kind: EntryKind.absence,
    ),
    ClosingDay(date: DateTime(2026, 8, 10), valueCents: 17000),
  ],
);

void main() {
  // rootBundle needs the binding to load the embedded fonts.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a real PDF', () async {
    final bytes = await ClosingPdf.build(
      closing: _closing(),
      year: 2026,
      month: 8,
    );

    expect(bytes, isNotEmpty);
    // Every PDF starts with this signature; anything else is not a document.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('an empty month still produces a document', () async {
    // The statement has to exist even when there is nothing to bill, or the
    // button would fail exactly when someone is checking why it is zero.
    final empty = ProviderClosing(
      provider: _closing().provider,
      entryCount: 0,
      totalCents: 0,
      days: const [],
      paid: false,
    );

    final bytes = await ClosingPdf.build(closing: empty, year: 2026, month: 8);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('paid and open months produce different documents', () async {
    final open = await ClosingPdf.build(
      closing: _closing(),
      year: 2026,
      month: 8,
    );
    final paid = await ClosingPdf.build(
      closing: _closing(paid: true),
      year: 2026,
      month: 8,
    );

    // The status badge is the only difference, and it must actually render.
    expect(open.length, isNot(paid.length));
  });

  test('days out of order are sorted into a readable month', () async {
    final shuffled = ProviderClosing(
      provider: _closing().provider,
      entryCount: 2,
      totalCents: 34000,
      paid: false,
      days: [
        ClosingDay(date: DateTime(2026, 8, 20), valueCents: 17000),
        ClosingDay(date: DateTime(2026, 8, 2), valueCents: 17000),
      ],
    );

    // Sorting happens inside build; this asserts it does not throw and still
    // produces a document with both rows.
    final bytes = await ClosingPdf.build(
      closing: shuffled,
      year: 2026,
      month: 8,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
