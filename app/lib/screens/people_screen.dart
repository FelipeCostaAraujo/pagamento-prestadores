import 'package:flutter/material.dart';

import '../format.dart';
import '../models/models.dart';
import '../main.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/ds_widgets.dart';
import '../widgets/money_field.dart';

/// Tab 3 — the prestadoras and their default day rate.
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final counts = state.dayCountByProvider;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        for (final provider in state.providers)
          Padding(
            padding: const EdgeInsets.only(bottom: DsSpace.s3),
            child: _ProviderCard(
              // Keyed by id so the text controllers follow the right person
              // when the list is reordered or one is removed.
              key: ValueKey(provider.id),
              state: state,
              provider: provider,
              dayCount: counts[provider.id] ?? 0,
            ),
          ),
        DsButton(
          label: '+ Nova prestadora',
          variant: DsButtonVariant.secondary,
          block: true,
          onPressed: state.addProvider,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(DsSpace.s1, DsSpace.s4, DsSpace.s1, 0),
          child: _FooterNote(),
        ),
        const SizedBox(height: DsSpace.s6),
        const _AccountSection(),
      ],
    );
  }
}

/// Who is signed in, and the way out.
///
/// The design has no settings screen, so this lives at the bottom of the
/// Cadastro tab — the one place already about configuration rather than data.
class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.maybeOf(context);
    if (auth == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.s1),
          child: Text('CONTA', style: DsText.caps()),
        ),
        const SizedBox(height: DsSpace.s3),
        DsCard(
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpace.s4,
            vertical: 14,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.person_outline,
                size: 22,
                color: DsColors.textMuted,
              ),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: Text(
                  auth.user?.username ?? '—',
                  style: DsText.body(
                    size: 15,
                    weight: DsWeight.bold,
                    height: 1.2,
                    color: DsColors.textStrong,
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: auth,
                builder: (context, _) => DsButton(
                  label: auth.busy ? 'Saindo…' : 'Sair',
                  variant: DsButtonVariant.secondary,
                  onPressed: auth.busy ? null : auth.logout,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      'O valor padrão é só uma sugestão — ao marcar um dia você pode alterar '
      'o valor daquela diária.',
      style: DsText.body(size: 12, height: 1.5, color: DsColors.textMuted),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    super.key,
    required this.state,
    required this.provider,
    required this.dayCount,
  });

  final AppState state;
  final Provider provider;
  final int dayCount;

  @override
  Widget build(BuildContext context) {
    final palette = DsPalette.at(provider.colorIndex);

    return DsCard(
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The colour bar is this prestadora's identity, matching her
              // calendar dots.
              Container(
                width: 10,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.dot,
                  borderRadius: BorderRadius.circular(DsRadius.pill),
                ),
              ),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: _NameField(
                  name: provider.name,
                  onCommitted: (name) =>
                      state.renameProvider(provider.id, name),
                ),
              ),
              _RemoveButton(state: state, provider: provider),
            ],
          ),
          const SizedBox(height: DsSpace.s3),
          const Divider(height: 1, color: DsColors.borderSubtle),
          const SizedBox(height: DsSpace.s3),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Valor padrão da diária',
                  style: DsText.body(
                    size: 13,
                    height: 1.3,
                    color: DsColors.textMuted,
                  ),
                ),
              ),
              MoneyField(
                valueCents: provider.defaultRateCents,
                semanticLabel: 'Valor padrão de ${provider.displayName}',
                onCommitted: (cents) =>
                    state.setProviderRate(provider.id, cents),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.s3),
          Text(
            dayCount == 1
                ? '1 diária marcada em ${monthName(state.month)}'
                : '$dayCount diárias marcadas em ${monthName(state.month)}',
            style: DsText.body(
              size: 12,
              height: 1.4,
              color: DsColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Borderless inline name field, committed on submit or when focus leaves.
class _NameField extends StatefulWidget {
  const _NameField({required this.name, required this.onCommitted});

  final String name;
  final ValueChanged<String> onCommitted;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.name);
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(_NameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.name != oldWidget.name && !_focusNode.hasFocus) {
      _controller.text = widget.name;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final name = _controller.text.trim();
    if (name != widget.name) widget.onCommitted(name);
  }

  @override
  Widget build(BuildContext context) {
    final style = DsText.display(size: 16, height: 1.2);

    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      style: style,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _commit(),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintText: 'Nome da prestadora',
        hintStyle: style.copyWith(color: DsColors.slate300),
      ),
    );
  }
}

/// Removing a prestadora is not in the design, but adding one without a way
/// back is a dead end. It archives rather than deletes, so her paid months and
/// worked days stay in the database.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.state, required this.provider});

  final AppState state;
  final Provider provider;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.close, size: 18),
      color: DsColors.textMuted,
      tooltip: 'Remover ${provider.displayName}',
      constraints: const BoxConstraints(
        minWidth: DsSize.touchMin,
        minHeight: DsSize.touchMin,
      ),
      onPressed: () => _confirm(context),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: DsColors.overlayScrim,
      builder: (dialogContext) => Dialog(
        backgroundColor: DsColors.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DsRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Remover ${provider.displayName}?',
                style: DsText.display(size: 18, height: 1.2),
              ),
              const SizedBox(height: 6),
              Text(
                'Ela sai da lista e do calendário. Os dias já marcados e os '
                'pagamentos ficam guardados no histórico.',
                style: DsText.body(size: 13, height: 1.5),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: DsButton(
                      label: 'Remover',
                      block: true,
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                    ),
                  ),
                  const SizedBox(width: DsSpace.s2),
                  DsButton(
                    label: 'Cancelar',
                    variant: DsButtonVariant.ghost,
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed ?? false) await state.deleteProvider(provider.id);
  }
}
