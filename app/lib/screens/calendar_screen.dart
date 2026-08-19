import 'package:flutter/material.dart';

import '../format.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/day_sheet.dart';
import '../widgets/ds_widgets.dart';

/// Tab 1 — mark who worked on which day.
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        _MonthCard(state: state),
        const SizedBox(height: DsSpace.s4),
        if (state.providers.isNotEmpty) ...[
          _Legend(state: state),
          const SizedBox(height: DsSpace.s4),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
          child: Text('ÚLTIMOS LANÇAMENTOS', style: DsText.caps()),
        ),
        const SizedBox(height: DsSpace.s3),
        _RecentList(state: state),
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.state});

  final AppState state;

  /// Weekday column headers, rotated when the week starts on Monday.
  List<String> get _headers => state.weekStart == WeekStart.sunday
      ? weekdayInitials
      : [...weekdayInitials.skip(1), weekdayInitials.first];

  /// How many blank cells precede day 1.
  int get _leadingBlanks {
    // DateTime.weekday is 1=Mon..7=Sun; convert to 0=Sun..6=Sat first.
    final firstWeekday = DateTime(state.year, state.month, 1).weekday % 7;
    return state.weekStart == WeekStart.sunday
        ? firstWeekday
        : (firstWeekday + 6) % 7;
  }

  int get _daysInMonth => DateTime(state.year, state.month + 1, 0).day;

  @override
  Widget build(BuildContext context) {
    // Pad to whole weeks so every row has seven cells.
    final cells = <int?>[
      ...List<int?>.filled(_leadingBlanks, null),
      ...List<int?>.generate(_daysInMonth, (i) => i + 1),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return DsCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: DsSpace.s4),
      child: Column(
        children: [
          _MonthNav(state: state),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final header in _headers)
                Expanded(
                  child: Center(
                    child: Text(
                      header,
                      style: DsText.caps(size: 11, tracking: 0.06),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var week = 0; week < cells.length ~/ 7; week++)
            Padding(
              padding: const EdgeInsets.only(bottom: DsSpace.s1),
              // IntrinsicHeight bounds the row to its tallest cell so `stretch`
              // can then make every cell that height — without it, stretch
              // inside the scrolling column asks for infinite height.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final day in cells.sublist(week * 7, week * 7 + 7))
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: day == null
                              ? const SizedBox(height: 46)
                              : _DayCell(state: state, day: day),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthNav extends StatelessWidget {
  const _MonthNav({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s1),
      child: Row(
        children: [
          _NavButton(
            icon: Icons.chevron_left,
            semanticLabel: 'Mês anterior',
            onTap: () => state.shiftMonth(-1),
          ),
          // Expanded rather than spaceBetween: the label takes whatever is
          // left between the two arrows and ellipsises instead of overflowing
          // when the month name is long or the font is wide.
          Expanded(
            child: Text(
              monthLabel(state.year, state.month),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DsText.display(size: 16, height: 1),
            ),
          ),
          _NavButton(
            icon: Icons.chevron_right,
            semanticLabel: 'Próximo mês',
            onTap: () => state.shiftMonth(1),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsRadius.md),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: DsColors.surfaceSunken,
            borderRadius: BorderRadius.circular(DsRadius.md),
          ),
          child: Icon(icon, size: 20, color: DsColors.textBody),
        ),
      ),
    );
  }
}

/// One day in the grid: the number, a dot per prestadora who worked, and
/// optionally the day's total.
class _DayCell extends StatelessWidget {
  const _DayCell({required this.state, required this.day});

  final AppState state;
  final int day;

  @override
  Widget build(BuildContext context) {
    final date = DateTime(state.year, state.month, day);
    final entries = state.entriesOn(date);
    final active = entries.isNotEmpty;
    final total = state.totalOn(date);

    return Semantics(
      button: true,
      label: active
          ? '$day, ${entries.length} diária(s), ${formatMoney(total)}'
          : '$day, sem diárias',
      child: InkWell(
        onTap: () => showDaySheet(context, state: state, date: date),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active ? DsColors.teal50 : DsColors.surfaceCard,
            border: Border.all(
              color: active ? DsColors.teal300 : DsColors.borderSubtle,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: DsText.body(
                  size: 15,
                  weight: DsWeight.bold,
                  height: 1,
                  color: active ? DsColors.teal700 : DsColors.textBody,
                ),
              ),
              const SizedBox(height: 3),
              // Fixed-height strip so cells with and without dots align.
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final entry in entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: DsDot(color: _dotColor(entry)),
                      ),
                  ],
                ),
              ),
              if (state.showDayValues && active) ...[
                const SizedBox(height: 3),
                Text(
                  formatCompactAmount(total),
                  style: DsText.body(size: 9, height: 1),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _dotColor(WorkEntry entry) {
    final provider = state.providerById(entry.providerId);
    // A dot with no matching prestadora means her record was archived; grey is
    // a deliberate "unknown", not a palette colour.
    if (provider == null) return DsColors.slate400;
    return DsPalette.at(provider.colorIndex).dot;
  }
}

/// Per-prestadora chips showing her colour and how many days she worked.
class _Legend extends StatelessWidget {
  const _Legend({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final counts = state.dayCountByProvider;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Wrap(
        spacing: DsSpace.s2,
        runSpacing: DsSpace.s2,
        children: [
          for (final provider in state.providers)
            _LegendChip(provider: provider, count: counts[provider.id] ?? 0),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.provider, required this.count});

  final Provider provider;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = DsPalette.at(provider.colorIndex);

    return DsPill(
      background: palette.tint,
      padding: const EdgeInsets.only(left: 10, right: DsSpace.s3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DsDot(color: palette.dot, size: 8),
          const SizedBox(width: 7),
          Text(
            provider.firstName,
            style: DsText.body(
              size: 12,
              weight: DsWeight.bold,
              height: 1,
              color: palette.dot,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${count}d',
            style: DsText.body(
              size: 12,
              weight: DsWeight.bold,
              height: 1,
              color: palette.dot.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final recent = state.recentEntries;

    if (recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 2,
          vertical: DsSpace.s2,
        ),
        child: Text(
          state.providers.isEmpty
              ? 'Cadastre uma prestadora para começar a marcar os dias.'
              : 'Nenhum dia marcado em ${monthName(state.month)}. '
                    'Toque em um dia do calendário para começar.',
          style: DsText.body(size: 13, height: 1.5),
        ),
      );
    }

    return Column(
      children: [
        for (final entry in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: DsSpace.s2),
            child: _RecentRow(state: state, entry: entry),
          ),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.state, required this.entry});

  final AppState state;
  final WorkEntry entry;

  @override
  Widget build(BuildContext context) {
    final provider = state.providerById(entry.providerId);
    final color = provider == null
        ? DsColors.slate400
        : DsPalette.at(provider.colorIndex).dot;

    return InkWell(
      onTap: () => showDaySheet(context, state: state, date: entry.date),
      borderRadius: BorderRadius.circular(DsRadius.md),
      child: DsCard(
        elevated: false,
        radius: DsRadius.md,
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: DsSpace.s3,
        ),
        child: Row(
          children: [
            DsDot(color: color, size: 10),
            const SizedBox(width: DsSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider?.displayName ?? '—',
                    style: DsText.body(
                      size: 14,
                      weight: DsWeight.bold,
                      height: 1.2,
                      color: DsColors.textStrong,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    recentDateLabel(entry.date),
                    style: DsText.body(
                      size: 12,
                      height: 1.3,
                      color: DsColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: DsSpace.s2),
            Text(
              formatMoney(entry.valueCents),
              style: DsText.body(
                size: 14,
                weight: DsWeight.bold,
                height: 1,
                color: DsColors.textStrong,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
