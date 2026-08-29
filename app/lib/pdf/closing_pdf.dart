import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../format.dart';
import '../models/models.dart';

/// Builds the month's statement as a PDF.
///
/// This is the document that goes to the prestadora, so it has to stand on its
/// own: every day listed with what it was worth, the absences visible rather
/// than quietly missing, and a total that can be checked by hand.
///
/// Deliberately built on the phone rather than the server — it needs no data
/// the app does not already have, and generating it locally means it also works
/// from the offline cache.
abstract final class ClosingPdf {
  /// Brand colours, matching the app so the document looks like it came from
  /// the same place.
  static const _ink = PdfColor.fromInt(0xFF141C20);
  static const _muted = PdfColor.fromInt(0xFF6B7C84);
  static const _line = PdfColor.fromInt(0xFFDCE3E6);
  static const _brand = PdfColor.fromInt(0xFF11675F);
  static const _absence = PdfColor.fromInt(0xFF94A4AB);

  /// The app's own text face, embedded in the document.
  ///
  /// Not cosmetic: the PDF library's built-in Helvetica has no Unicode support,
  /// so "Marília", "diária" and "mês" would come out with missing glyphs. A
  /// statement about someone's pay cannot misspell her name.
  static Future<pw.ThemeData> _theme() async {
    final regular = await rootBundle.load(
      'assets/fonts/AtkinsonHyperlegible-Regular.ttf',
    );
    final bold = await rootBundle.load(
      'assets/fonts/AtkinsonHyperlegible-Bold.ttf',
    );
    final italic = await rootBundle.load(
      'assets/fonts/AtkinsonHyperlegible-Italic.ttf',
    );
    return pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
      italic: pw.Font.ttf(italic),
    );
  }

  static Future<Uint8List> build({
    required ProviderClosing closing,
    required int year,
    required int month,
  }) async {
    final doc = pw.Document(
      title:
          'Fechamento ${monthLabel(year, month)} — '
          '${closing.provider.displayName}',
      author: 'Diárias',
      theme: await _theme(),
    );

    // Sorted so the document reads as a diary of the month.
    final days = [...closing.days]..sort((a, b) => a.date.compareTo(b.date));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 44, 40, 44),
        header: (context) =>
            context.pageNumber == 1 ? _header(closing, year, month) : _rule(),
        footer: (context) => _footer(context),
        build: (context) => [
          pw.SizedBox(height: 18),
          _summary(closing),
          pw.SizedBox(height: 22),
          _daysTable(days),
          pw.SizedBox(height: 22),
          _total(closing),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _header(ProviderClosing closing, int year, int month) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'FECHAMENTO DO MÊS',
                  style: pw.TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.6,
                    color: _muted,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  closing.provider.displayName,
                  style: pw.TextStyle(
                    fontSize: 22,
                    color: _ink,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  monthLabel(year, month),
                  style: const pw.TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
            _statusBadge(closing.paid),
          ],
        ),
        pw.SizedBox(height: 14),
        _rule(),
      ],
    );
  }

  static pw.Widget _rule() => pw.Container(
    height: 1.5,
    color: _brand,
    margin: const pw.EdgeInsets.only(bottom: 2),
  );

  static pw.Widget _statusBadge(bool paid) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: pw.BoxDecoration(
        color: paid
            ? const PdfColor.fromInt(0xFFDEF3E7)
            : const PdfColor.fromInt(0xFFFBEFCB),
        // Not a pill radius: dart_pdf does not clamp an oversized corner the
        // way Flutter does, and 999 on a small box drew a shape that swallowed
        // the header.
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Text(
        paid ? 'PAGO' : 'EM ABERTO',
        style: pw.TextStyle(
          fontSize: 9,
          letterSpacing: 1.1,
          fontWeight: pw.FontWeight.bold,
          color: paid
              ? const PdfColor.fromInt(0xFF168F52)
              : const PdfColor.fromInt(0xFF8A6000),
        ),
      ),
    );
  }

  /// The counts, so the totals can be sanity-checked before reading the table.
  static pw.Widget _summary(ProviderClosing closing) {
    final worked = closing.entryCount - closing.halfCount;
    return pw.Row(
      children: [
        _stat('Diárias integrais', '$worked'),
        _stat('Meias diárias', '${closing.halfCount}'),
        _stat('Faltas', '${closing.absenceCount}'),
      ],
    );
  }

  static pw.Widget _stat(String label, String value) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.only(right: 10),
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _line),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 7.5,
                letterSpacing: 1,
                color: _muted,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 18,
                color: _ink,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _daysTable(List<ClosingDay> days) {
    if (days.isEmpty) {
      return pw.Text(
        'Nenhum dia registrado neste mês.',
        style: const pw.TextStyle(fontSize: 11, color: _muted),
      );
    }

    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1.4),
        1: pw.FlexColumnWidth(2.2),
        2: pw.FlexColumnWidth(1.8),
        3: pw.FlexColumnWidth(1.6),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _line, width: 1)),
          ),
          children: [
            _th('DIA'),
            _th('DIA DA SEMANA'),
            _th('TIPO'),
            _th('VALOR', alignRight: true),
          ],
        ),
        for (final day in days)
          pw.TableRow(
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: _line, width: 0.5),
              ),
            ),
            children: [
              _td(shortDayLabel(day.date), absence: !day.kind.billable),
              _td(
                capitalize(weekdayName(day.date)),
                absence: !day.kind.billable,
              ),
              _td(day.kind.label, absence: !day.kind.billable),
              _td(
                // A falta shows the word, not "R$ 0,00" — the day is recorded,
                // nothing is owed for it, and a zero reads like an error.
                day.kind.billable ? formatMoney(day.valueCents) : '—',
                alignRight: true,
                absence: !day.kind.billable,
              ),
            ],
          ),
      ],
    );
  }

  static pw.Widget _th(String text, {bool alignRight = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 8),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: 7.5,
        letterSpacing: 1,
        color: _muted,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );

  static pw.Widget _td(
    String text, {
    bool alignRight = false,
    bool absence = false,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 8),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: 10.5,
        color: absence ? _absence : _ink,
        fontStyle: absence ? pw.FontStyle.italic : pw.FontStyle.normal,
      ),
    ),
  );

  static pw.Widget _total(ProviderClosing closing) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFECFBF8),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            'Total do mês',
            style: pw.TextStyle(
              fontSize: 12,
              color: _brand,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            formatMoney(closing.totalCents),
            style: pw.TextStyle(
              fontSize: 20,
              color: _ink,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context context) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Gerado pelo app Diárias',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ],
      ),
    );
  }
}
