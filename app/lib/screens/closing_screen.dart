import 'package:flutter/material.dart';

import '../format.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/ds_widgets.dart';
import '../widgets/share_dialog.dart';

/// Tab 2 — the month's total per prestadora, and marking it paid.
class ClosingScreen extends StatelessWidget {
  const ClosingScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final closings = state.closing.providers;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        if (closings.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s4),
            child: Text(
              'Nenhuma prestadora cadastrada ainda.',
              style: DsText.body(size: 14, height: 1.5),
            ),
          )
        else
          for (final closing in closings)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _ClosingCard(state: state, closing: closing),
            ),
        _SummaryBlock(state: state),
      ],
    );
  }
}

class _ClosingCard extends StatelessWidget {
  const _ClosingCard({required this.state, required this.closing});

  final AppState state;
  final ProviderClosing closing;

  String get _countLabel {
    final month = monthName(state.month);
    return closing.entryCount == 1
        ? '1 diária em $month'
        : '${closing.entryCount} diárias em $month';
  }

  @override
  Widget build(BuildContext context) {
    final provider = closing.provider;
    final palette = DsPalette.at(provider.colorIndex);
    // Nothing worked means nothing to pay — the API rejects it too.
    final canPay = closing.entryCount > 0;

    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DsAvatar(name: provider.displayName, color: palette.dot),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.displayName,
                      style: DsText.display(size: 16, height: 1.2),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _countLabel,
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
              _StatusPill(paid: closing.paid),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: DsColors.borderSubtle),
          const SizedBox(height: DsSpace.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'Total do mês',
                  style: DsText.body(
                    size: 13,
                    height: 1,
                    color: DsColors.textMuted,
                  ),
                ),
              ),
              Text(
                formatMoney(closing.totalCents),
                style: DsText.display(size: 26, height: 1),
              ),
            ],
          ),
          if (closing.days.isNotEmpty) ...[
            const SizedBox(height: DsSpace.s3),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final day in closing.days) _DayChip(day: day)],
            ),
          ],
          const SizedBox(height: DsSpace.s4),
          Row(
            children: [
              Expanded(
                child: DsButton(
                  label: closing.paid
                      ? 'Desfazer pagamento'
                      : 'Marcar como pago',
                  variant: closing.paid
                      ? DsButtonVariant.ghost
                      : DsButtonVariant.primary,
                  block: true,
                  onPressed: canPay ? () => _togglePaid(context) : null,
                ),
              ),
              const SizedBox(width: DsSpace.s2),
              DsButton(
                label: 'Enviar',
                variant: DsButtonVariant.secondary,
                onPressed: canPay
                    ? () => showShareDialog(
                        context,
                        state: state,
                        closing: closing,
                      )
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _togglePaid(BuildContext context) {
    final name = closing.provider.firstName;
    state.setPaid(
      closing.provider.id,
      !closing.paid,
      toast: closing.paid
          ? 'Pagamento de $name reaberto'
          : '${formatMoney(closing.totalCents)} pagos a $name',
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.paid});

  final bool paid;

  @override
  Widget build(BuildContext context) {
    return DsPill(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      background: paid ? DsColors.paidBg : DsColors.openBg,
      child: Text(
        paid ? 'Pago' : 'Em aberto',
        style: DsText.body(
          size: 12,
          weight: DsWeight.bold,
          height: 1,
          color: paid ? DsColors.paidFg : DsColors.openFg,
        ),
      ),
    );
  }
}

/// "03/08 R$ 180,00" — one chip per worked day.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.day});

  final ClosingDay day;

  @override
  Widget build(BuildContext context) {
    return DsPill(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      background: DsColors.surfaceSunken,
      border: DsColors.borderSubtle,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            shortDayLabel(day.date),
            style: DsText.body(
              size: 12,
              weight: DsWeight.bold,
              height: 1,
              color: DsColors.textBody,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            formatMoney(day.valueCents),
            style: DsText.body(size: 12, height: 1, color: DsColors.textBody),
          ),
        ],
      ),
    );
  }
}

/// The soft brand panel summarising the month.
class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({required this.state});

  final AppState state;

  String get _summary {
    final closing = state.closing;
    final open = closing.openCount;
    if (open == 0) {
      final days = closing.workedDays;
      final worked = days == 1 ? '1 dia trabalhado' : '$days dias trabalhados';
      return closing.workedDays == 0
          ? 'Nenhum dia marcado neste mês.'
          : 'Tudo pago. $worked no mês.';
    }
    final subject = open == 1
        ? '1 prestadora ainda'
        : '$open prestadoras ainda';
    return '$subject com valor em aberto, somando '
        '${formatMoney(closing.outstandingCents)}.';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: DsSpace.s4),
      decoration: BoxDecoration(
        gradient: DsGradients.brandSoft,
        border: Border.all(color: DsColors.teal100),
        borderRadius: BorderRadius.circular(DsRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fechamento de ${monthLabel(state.year, state.month)}',
            style: DsText.body(
              size: 13,
              weight: DsWeight.bold,
              height: 1.3,
              color: DsColors.teal700,
            ),
          ),
          const SizedBox(height: 6),
          Text(_summary, style: DsText.body(size: 13, height: 1.5)),
        ],
      ),
    );
  }
}
