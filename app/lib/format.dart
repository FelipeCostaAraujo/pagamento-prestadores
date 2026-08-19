/// pt-BR formatting for money and dates.
///
/// The month and weekday names are spelled out here rather than taken from
/// `intl` so they match the design doc exactly (lowercase, "março") with no
/// locale-data initialisation step.
library;

const monthNames = <String>[
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

/// Indexed by `DateTime.weekday % 7`, so Sunday (weekday 7) maps to 0.
const weekdayNames = <String>[
  'domingo',
  'segunda',
  'terça',
  'quarta',
  'quinta',
  'sexta',
  'sábado',
];

/// Single-letter column headers, Sunday first — the design's `['D','S','T','Q','Q','S','S']`.
const weekdayInitials = <String>['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

String capitalize(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

String monthName(int month) => monthNames[month - 1];

/// "Agosto de 2026" — the header and month-navigation label.
String monthLabel(int year, int month) =>
    '${capitalize(monthName(month))} de $year';

String weekdayName(DateTime date) => weekdayNames[date.weekday % 7];

/// "Segunda, 3 de agosto" — the day sheet's subtitle.
String longDayLabel(DateTime date) =>
    '${capitalize(weekdayName(date))}, ${date.day} de ${monthName(date.month)}';

/// "03/08" — the compact day chips on the closing cards.
String shortDayLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

/// "domingo, 3 de agosto" — the recent-entries list.
String recentDateLabel(DateTime date) =>
    '${weekdayName(date)}, ${date.day} de ${monthName(date.month)}';

/// Groups an integer's digits with "." every three places: 1800 -> "1.800".
String _groupThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// "R$ 1.800,00" — full currency, used everywhere a total is shown.
String formatMoney(int cents) => 'R\$ ${formatAmount(cents)}';

/// "1.800,00" — the amount without the currency symbol, for inputs and for
/// rows that render "R$" as a separate prefix element.
String formatAmount(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final decimals = (abs % 100).toString().padLeft(2, '0');
  return '$sign${_groupThousands(abs ~/ 100)},$decimals';
}

/// "180" or "180,50" — drops trailing zero cents so the tiny per-day labels in
/// the calendar stay legible.
String formatCompactAmount(int cents) {
  if (cents % 100 == 0) return _groupThousands(cents.abs() ~/ 100);
  return formatAmount(cents);
}

/// Parses user input into cents, accepting both Brazilian and plain forms:
/// "180", "180,50", "1.800,00", "180.50".
///
/// Returns null when nothing numeric was entered, so callers can distinguish
/// "cleared the field" from "typed a zero".
int? parseCents(String input) {
  var text = input.trim();
  if (text.isEmpty) return null;

  // Drop everything that cannot be part of a number.
  text = text.replaceAll(RegExp(r'[^\d,.\-]'), '');
  if (text.isEmpty || text == '-') return null;

  final lastComma = text.lastIndexOf(',');
  final lastDot = text.lastIndexOf('.');

  // Whichever separator comes last is the decimal one; the other groups
  // thousands. "1.800,00" -> comma decimal; "1,800.00" -> dot decimal.
  final String normalized;
  if (lastComma > lastDot) {
    normalized = text.replaceAll('.', '').replaceAll(',', '.');
  } else if (lastDot > lastComma) {
    normalized = text.replaceAll(',', '');
  } else {
    normalized = text;
  }

  final value = double.tryParse(normalized);
  if (value == null) return null;
  // Round rather than truncate so "180,999" does not become 180,99.
  return (value * 100).round();
}
