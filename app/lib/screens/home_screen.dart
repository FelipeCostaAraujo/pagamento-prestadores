import 'package:flutter/material.dart';

import '../format.dart';
import '../main.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_toast.dart';
import '../widgets/ds_widgets.dart';
import 'calendar_screen.dart';
import 'closing_screen.dart';
import 'people_screen.dart';

/// The app shell: brand hero header, the active tab, and the bottom bar.
///
/// The three tabs are the whole app — the design is explicit that there is
/// nothing more ("Três telas, nada mais").
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Scaffold(
      backgroundColor: DsColors.bgPage,
      body: Stack(
        children: [
          Column(
            children: [
              _HeroHeader(state: state),
              Expanded(child: _Body(state: state)),
              _BottomBar(state: state),
            ],
          ),
          // Sits above the bottom bar, as in the design.
          Positioned(
            left: DsSpace.s4,
            right: DsSpace.s4,
            bottom: 104 + MediaQuery.paddingOf(context).bottom,
            child: AppToast(state: state),
          ),
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.state});

  final AppState state;

  /// (kicker, title) per tab, from the design's `titles` map.
  (String, String) get _titles => switch (state.tab) {
    AppTab.calendar => ('Marcar dias', monthLabel(state.year, state.month)),
    AppTab.closing => ('Fechamento', monthLabel(state.year, state.month)),
    AppTab.people => ('Cadastro', 'Prestadoras'),
  };

  @override
  Widget build(BuildContext context) {
    final (kicker, title) = _titles;
    final onBrandMuted = Colors.white.withValues(alpha: 0.62);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: DsGradients.hero),
      padding: EdgeInsets.fromLTRB(
        22,
        MediaQuery.paddingOf(context).top + DsSpace.s4,
        22,
        20,
      ),
      // The design's header is one line tall and must stay that way whatever
      // the amount reads. An unbounded right-hand column would take as much
      // width as the number needs and squeeze the left side until the kicker
      // wrapped — the fix is to split the row by weight (3:2) so neither side
      // can starve the other, then let text scale down inside its share.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kicker.toUpperCase(),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: DsText.caps(
                    size: 11,
                    color: onBrandMuted,
                    tracking: 0.14,
                  ),
                ),
                const SizedBox(height: DsSpace.s2),
                // scaleDown never enlarges, so the common case still renders at
                // the design's 25px and only a long month/narrow screen shrinks.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    style: DsText.display(
                      size: 25,
                      height: 1.15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: DsSpace.s3),
          // Loose fit: takes only the width the total needs, up to 2/5.
          Flexible(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'A PAGAR',
                  maxLines: 1,
                  softWrap: false,
                  style: DsText.caps(
                    size: 10,
                    color: onBrandMuted,
                    tracking: 0.1,
                  ),
                ),
                const SizedBox(height: 6),
                // Same guard for an unusually large total.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    formatMoney(state.closing.outstandingCents),
                    maxLines: 1,
                    softWrap: false,
                    style: DsText.display(
                      size: 21,
                      height: 1.1,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    // Only the very first load blanks the screen; later refreshes keep the
    // current content visible so the UI doesn't flash on every tap.
    if (!state.initialLoadDone) {
      return const Center(
        child: CircularProgressIndicator(color: DsColors.brand),
      );
    }
    if (state.error != null && state.providers.isEmpty) {
      return _ErrorState(state: state);
    }

    return switch (state.tab) {
      AppTab.calendar => CalendarScreen(state: state),
      AppTab.closing => ClosingScreen(state: state),
      AppTab.people => PeopleScreen(state: state),
    };
  }
}

/// Shown when the app has no data at all — almost always "the API isn't
/// running", so it names that and offers a retry rather than an empty screen.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DsSpace.s5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 44,
              color: DsColors.textMuted,
            ),
            const SizedBox(height: DsSpace.s4),
            Text(
              'Sem conexão com o servidor',
              textAlign: TextAlign.center,
              style: DsText.display(size: 18, height: 1.25),
            ),
            const SizedBox(height: DsSpace.s2),
            Text(
              state.error!,
              textAlign: TextAlign.center,
              style: DsText.body(size: 13, height: 1.45),
            ),
            const SizedBox(height: DsSpace.s5),
            DsButton(
              label: state.loading ? 'Tentando…' : 'Tentar de novo',
              onPressed: state.loading ? null : state.load,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.state});

  final AppState state;

  /// The design uses 2px-stroke line icons; Material's outlined set is the
  /// closest match available without shipping custom SVGs.
  static const _tabs = <(AppTab, String, IconData)>[
    (AppTab.calendar, 'Calendário', Icons.calendar_today_outlined),
    (AppTab.closing, 'Fechamento', Icons.receipt_long_outlined),
    (AppTab.people, 'Prestadoras', Icons.people_outline),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: DsColors.surfaceCard,
        border: Border(top: BorderSide(color: DsColors.borderSubtle)),
      ),
      padding: EdgeInsets.fromLTRB(
        DsSpace.s3,
        DsSpace.s2,
        DsSpace.s3,
        // 30px in the design, but never less than the home-indicator inset.
        MediaQuery.paddingOf(context).bottom + DsSpace.s2,
      ),
      child: Row(
        children: [
          for (final (tab, label, icon) in _tabs)
            Expanded(
              child: _TabButton(
                label: label,
                icon: icon,
                selected: state.tab == tab,
                onTap: () => state.setTab(tab),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? DsColors.teal600 : DsColors.textMuted;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DsRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DsSpace.s2),
          child: Column(
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DsText.body(
                  size: 11,
                  weight: DsWeight.bold,
                  height: 1,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
