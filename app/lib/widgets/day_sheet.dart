import 'package:flutter/material.dart';

import '../format.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'ds_widgets.dart';
import 'money_field.dart';

/// Opens the "Quem trabalhou?" sheet for [date].
///
/// Every toggle and value edit is persisted as it happens, so "Salvar dia" only
/// dismisses — there is nothing left to save. The design's flow deliberately
/// keeps that button so the sheet has an obvious way out.
Future<void> showDaySheet(
  BuildContext context, {
  required AppState state,
  required DateTime date,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: DsColors.overlayScrim,
    isScrollControlled: true,
    builder: (_) => _DaySheet(state: state, date: date),
  );
}

class _DaySheet extends StatelessWidget {
  const _DaySheet({required this.state, required this.date});

  final AppState state;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    // The sheet lives on a route above AppScope, so it subscribes to the state
    // object directly to pick up changes made from inside it.
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: DsColors.surfaceCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: DsShadows.xl,
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            // Clear the keyboard and the home indicator.
            MediaQuery.viewInsetsOf(context).bottom +
                MediaQuery.paddingOf(context).bottom +
                DsSpace.s5,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: DsColors.borderStrong,
                      borderRadius: BorderRadius.circular(DsRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: DsSpace.s4),
                Text(
                  'Quem trabalhou?',
                  style: DsText.display(size: 19, height: 1.2),
                ),
                const SizedBox(height: 5),
                Text(
                  longDayLabel(date),
                  style: DsText.body(
                    size: 13,
                    height: 1.3,
                    color: DsColors.textMuted,
                  ),
                ),
                const SizedBox(height: 18),
                if (state.providers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: DsSpace.s4),
                    child: Text(
                      'Nenhuma prestadora cadastrada. Adicione uma na aba '
                      'Prestadoras para marcar os dias.',
                      style: DsText.body(size: 13, height: 1.5),
                    ),
                  )
                else
                  for (final provider in state.providers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DsSpace.s3),
                      child: _ProviderRow(
                        state: state,
                        provider: provider,
                        date: date,
                      ),
                    ),
                const SizedBox(height: DsSpace.s3),
                DsButton(
                  label: 'Salvar dia',
                  size: DsButtonSize.lg,
                  block: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.state,
    required this.provider,
    required this.date,
  });

  final AppState state;
  final Provider provider;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final entry = state.entryFor(provider.id, date);
    final worked = entry != null;
    final palette = DsPalette.at(provider.colorIndex);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: DsSpace.s3),
      decoration: BoxDecoration(
        color: worked ? palette.tint : DsColors.surfaceCard,
        border: Border.all(
          color: worked ? palette.dot : DsColors.borderSubtle,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(DsRadius.md),
      ),
      child: Column(
        children: [
          Semantics(
            checked: worked,
            label: provider.displayName,
            child: InkWell(
              onTap: () => state.toggleEntry(provider.id, date),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: DsSize.touchMin),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: worked ? palette.dot : Colors.transparent,
                        border: Border.all(
                          color: worked ? palette.dot : DsColors.borderStrong,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: worked
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: DsSpace.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            provider.displayName,
                            style: DsText.body(
                              size: 15,
                              weight: DsWeight.bold,
                              height: 1.2,
                              color: DsColors.textStrong,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            worked
                                ? 'Trabalhou neste dia'
                                : 'Valor padrão ${formatMoney(provider.defaultRateCents)}',
                            style: DsText.body(
                              size: 12,
                              height: 1.3,
                              color: DsColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (worked) ...[
            const SizedBox(height: DsSpace.s3),
            const Divider(height: 1, color: DsColors.borderSubtle),
            const SizedBox(height: DsSpace.s3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Valor desta diária',
                    style: DsText.body(size: 13, height: 1),
                  ),
                ),
                MoneyField(
                  // Keyed by entry so switching days rebuilds the controller
                  // with the right amount instead of reusing the old text.
                  key: ValueKey('value-${entry.id}'),
                  valueCents: entry.valueCents,
                  width: 62,
                  semanticLabel: 'Valor da diária de ${provider.displayName}',
                  onCommitted: (cents) =>
                      state.setEntryValue(provider.id, date, cents),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
