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
    // The row is already showing the optimistic result; this only marks that
    // the server has not confirmed it yet, and blocks a second tap in between.
    final saving = state.isPending(AppState.entryKey(provider.id, date));

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
              onTap: saving ? null : () => state.toggleEntry(provider.id, date),
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
                      child: saving
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: worked ? Colors.white : palette.dot,
                              ),
                            )
                          : worked
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
                                ? switch (entry.kind) {
                                    EntryKind.full => 'Trabalhou o dia inteiro',
                                    EntryKind.half => 'Trabalhou meio período',
                                    EntryKind.absence => 'Não veio neste dia',
                                  }
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
            _KindSelector(
              selected: entry.kind,
              accent: palette.dot,
              enabled: !saving,
              onChanged: (kind) => state.setEntryKind(provider.id, date, kind),
            ),
            // A falta não tem valor a editar — o campo sumir deixa isso óbvio.
            if (entry.kind.billable) ...[
              const SizedBox(height: DsSpace.s3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.kind == EntryKind.half
                          ? 'Valor desta meia diária'
                          : 'Valor desta diária',
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
        ],
      ),
    );
  }
}

/// Three-way choice for a marked day.
///
/// Tapping the row still just marks the day worked — the common case stays one
/// tap. This appears only once a day is marked, for the two cases that are not
/// a normal full day.
class _KindSelector extends StatelessWidget {
  const _KindSelector({
    required this.selected,
    required this.accent,
    required this.enabled,
    required this.onChanged,
  });

  final EntryKind selected;
  final Color accent;
  final bool enabled;
  final ValueChanged<EntryKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final kind in EntryKind.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _KindOption(
                kind: kind,
                selected: kind == selected,
                accent: accent,
                enabled: enabled,
                onTap: () => onChanged(kind),
              ),
            ),
          ),
      ],
    );
  }
}

class _KindOption extends StatelessWidget {
  const _KindOption({
    required this.kind,
    required this.selected,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });

  final EntryKind kind;
  final bool selected;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: kind.label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(DsRadius.sm),
        child: AnimatedContainer(
          duration: DsMotion.fast,
          curve: DsMotion.easeOut,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent : DsColors.surfaceCard,
            border: Border.all(
              color: selected ? accent : DsColors.borderStrong,
            ),
            borderRadius: BorderRadius.circular(DsRadius.sm),
          ),
          child: Text(
            kind.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DsText.body(
              size: 12,
              weight: DsWeight.bold,
              height: 1,
              color: selected ? Colors.white : DsColors.textBody,
            ),
          ),
        ),
      ),
    );
  }
}
