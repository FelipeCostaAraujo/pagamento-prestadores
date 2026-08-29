import 'package:flutter/material.dart';

import '../format.dart';
import '../models/models.dart';
import '../main.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/ds_widgets.dart';
import '../widgets/money_field.dart';
import 'sessions_screen.dart';

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
          loading: state.isPending(AppState.addProviderKey),
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
                  auth.user?.username ?? 'Sessão salva neste aparelho',
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
        const SizedBox(height: DsSpace.s2),
        DsCard(
          padding: EdgeInsets.zero,
          elevated: false,
          child: ListTile(
            leading: const Icon(
              Icons.devices_other,
              size: 22,
              color: DsColors.textMuted,
            ),
            title: Text(
              'Aparelhos conectados',
              style: DsText.body(
                size: 14,
                weight: DsWeight.bold,
                height: 1.2,
                color: DsColors.textStrong,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: DsColors.textMuted,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SessionsScreen(api: auth.api),
              ),
            ),
          ),
        ),
        const SizedBox(height: DsSpace.s2),
        const _ReminderToggle(),
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
          const Divider(height: 1, color: DsColors.borderSubtle),
          const SizedBox(height: DsSpace.s3),
          Row(
            children: [
              Expanded(
                child: Text(
                  'WhatsApp',
                  style: DsText.body(
                    size: 13,
                    height: 1.3,
                    color: DsColors.textMuted,
                  ),
                ),
              ),
              SizedBox(
                width: 168,
                child: _PhoneField(
                  phone: provider.phone,
                  onCommitted: (phone) =>
                      state.setProviderPhone(provider.id, phone),
                ),
              ),
            ],
          ),
          const SizedBox(height: DsSpace.s3),
          const Divider(height: 1, color: DsColors.borderSubtle),
          const SizedBox(height: DsSpace.s3),
          _ScheduleEditor(state: state, provider: provider),
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

/// Phone number for the WhatsApp hand-off. Committed on submit or focus loss,
/// like the other inline fields.
class _PhoneField extends StatefulWidget {
  const _PhoneField({required this.phone, required this.onCommitted});

  final String phone;
  final ValueChanged<String> onCommitted;

  @override
  State<_PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<_PhoneField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.phone);
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(_PhoneField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phone != oldWidget.phone && !_focusNode.hasFocus) {
      _controller.text = widget.phone;
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
    final phone = _controller.text.trim();
    if (phone != widget.phone) widget.onCommitted(phone);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DsSize.controlMd,
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3),
      decoration: BoxDecoration(
        color: DsColors.surfaceCard,
        border: Border.all(color: DsColors.borderStrong, width: 1.5),
        borderRadius: BorderRadius.circular(DsRadius.md),
      ),
      child: Center(
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _commit(),
          style: DsText.body(
            size: 15,
            weight: DsWeight.bold,
            height: 1,
            color: DsColors.textStrong,
          ),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: '(11) 90000-0000',
            hintStyle: DsText.body(
              size: 15,
              height: 1,
              color: DsColors.slate300,
            ),
          ),
        ),
      ),
    );
  }
}

/// Turns this device's push reminders on or off.
class _ReminderToggle extends StatefulWidget {
  const _ReminderToggle();

  @override
  State<_ReminderToggle> createState() => _ReminderToggleState();
}

class _ReminderToggleState extends State<_ReminderToggle> {
  bool? _enabled;
  bool _busy = false;

  Future<void> _load() async {
    final reminders = ReminderScope.maybeOf(context);
    if (reminders == null) return;
    final enabled = await reminders.isEnabled();
    if (mounted) setState(() => _enabled = enabled);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enabled == null) _load();
  }

  Future<void> _toggle(bool value) async {
    final reminders = ReminderScope.maybeOf(context);
    if (reminders == null || _busy) return;

    setState(() => _busy = true);
    final result = await reminders.setEnabled(value);
    if (!mounted) return;
    setState(() {
      _enabled = result;
      _busy = false;
    });

    // The OS can refuse; saying so beats a switch that silently springs back.
    if (value && !result && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permita as notificações do app para receber o lembrete.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ReminderScope.maybeOf(context) == null) {
      return const SizedBox.shrink();
    }

    return DsCard(
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: 6),
      elevated: false,
      child: Row(
        children: [
          const Icon(
            Icons.notifications_none,
            size: 22,
            color: DsColors.textMuted,
          ),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Lembretes no celular',
                  style: DsText.body(
                    size: 14,
                    weight: DsWeight.bold,
                    height: 1.2,
                    color: DsColors.textStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Avisos para anotar a diária e para pagar o mês',
                  style: DsText.body(
                    size: 12,
                    height: 1.3,
                    color: DsColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _enabled ?? false,
            onChanged: _busy || _enabled == null ? null : _toggle,
            activeThumbColor: DsColors.brand,
          ),
        ],
      ),
    );
  }
}

/// Which weekdays this person is expected, and when to be asked about the day.
///
/// Empty means no routine — the case for someone who only comes when called,
/// and the reason this is opt-in rather than a default schedule.
class _ScheduleEditor extends StatelessWidget {
  const _ScheduleEditor({required this.state, required this.provider});

  final AppState state;
  final Provider provider;

  static const _initials = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
  static const _names = [
    'domingo',
    'segunda',
    'terça',
    'quarta',
    'quinta',
    'sexta',
    'sábado',
  ];

  void _toggle(int weekday) {
    final next = [...provider.remindWeekdays];
    if (!next.remove(weekday)) next.add(weekday);
    next.sort();
    state.setProviderSchedule(provider.id, weekdays: next);
  }

  Future<void> _pickTime(BuildContext context) async {
    final parts = provider.remindAt.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 19,
        minute: int.tryParse(parts.last) ?? 0,
      ),
      helpText: 'Lembrar às',
    );
    if (picked == null) return;
    final value =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    await state.setProviderSchedule(provider.id, remindAt: value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = DsPalette.at(provider.colorIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Dias que costuma vir',
                style: DsText.body(
                  size: 13,
                  height: 1.3,
                  color: DsColors.textMuted,
                ),
              ),
            ),
            if (provider.hasSchedule)
              GestureDetector(
                onTap: () => _pickTime(context),
                child: DsPill(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3),
                  background: DsColors.surfaceSunken,
                  border: DsColors.borderSubtle,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 14,
                        color: DsColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        provider.remindAt,
                        style: DsText.body(
                          size: 13,
                          weight: DsWeight.bold,
                          height: 1,
                          color: DsColors.textStrong,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: DsSpace.s2),
        Row(
          children: [
            for (var day = 0; day < 7; day++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _WeekdayToggle(
                    label: _initials[day],
                    semanticLabel: _names[day],
                    selected: provider.remindWeekdays.contains(day),
                    accent: palette.dot,
                    onTap: () => _toggle(day),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: DsSpace.s2),
        Text(
          provider.hasSchedule
              ? 'Você será lembrado às ${provider.remindAt} de anotar a diária, '
                    'se ainda não tiver anotado.'
              : 'Sem dias fixos — nenhum lembrete será enviado.',
          style: DsText.body(size: 12, height: 1.4, color: DsColors.textMuted),
        ),
      ],
    );
  }
}

class _WeekdayToggle extends StatelessWidget {
  const _WeekdayToggle({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsRadius.sm),
        child: AnimatedContainer(
          duration: DsMotion.fast,
          curve: DsMotion.easeOut,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent : DsColors.surfaceCard,
            border: Border.all(
              color: selected ? accent : DsColors.borderStrong,
            ),
            borderRadius: BorderRadius.circular(DsRadius.sm),
          ),
          child: Text(
            label,
            style: DsText.body(
              size: 13,
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
