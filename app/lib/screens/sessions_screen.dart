import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../format.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/ds_widgets.dart';

/// The devices signed in to this account, and the way to sign them out.
///
/// This is the practical answer to a lost phone, and the visible half of the
/// refresh-token protection: if a session shows up that you do not recognise,
/// you can end it here.
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  List<SessionInfo>? _sessions;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final sessions = await widget.api.listSessions();
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _revoke(SessionInfo session) async {
    setState(() => _busy = true);
    try {
      await widget.api.revokeSession(session.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeOthers() async {
    setState(() => _busy = true);
    try {
      final revoked = await widget.api.revokeOtherSessions();
      await _load();
      if (!mounted) return;
      final message = revoked == 1
          ? '1 aparelho desconectado'
          : '$revoked aparelhos desconectados';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    final others = sessions?.where((s) => !s.current).length ?? 0;

    return Scaffold(
      backgroundColor: DsColors.bgPage,
      appBar: AppBar(
        backgroundColor: DsColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        title: Text('Aparelhos conectados', style: DsText.display(size: 18)),
      ),
      body: switch ((sessions, _error)) {
        (_, final String error) => _Message(text: error, onRetry: _load),
        (null, _) => const Center(
          child: CircularProgressIndicator(color: DsColors.brand),
        ),
        (final list?, _) => ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          children: [
            for (final session in list)
              Padding(
                padding: const EdgeInsets.only(bottom: DsSpace.s3),
                child: _SessionCard(
                  session: session,
                  busy: _busy,
                  onRevoke: () => _revoke(session),
                ),
              ),
            if (others > 0) ...[
              const SizedBox(height: DsSpace.s3),
              DsButton(
                label: 'Sair dos outros aparelhos',
                variant: DsButtonVariant.secondary,
                block: true,
                loading: _busy,
                onPressed: _revokeOthers,
              ),
            ],
            const SizedBox(height: DsSpace.s4),
            Text(
              'Se aparecer um aparelho que você não reconhece, desconecte e '
              'troque a sua senha.',
              style: DsText.body(
                size: 12,
                height: 1.5,
                color: DsColors.textMuted,
              ),
            ),
          ],
        ),
      },
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.busy,
    required this.onRevoke,
  });

  final SessionInfo session;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: 14),
      child: Row(
        children: [
          Icon(
            session.current ? Icons.smartphone : Icons.devices_other,
            size: 22,
            color: session.current ? DsColors.brand : DsColors.textMuted,
          ),
          const SizedBox(width: DsSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        session.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DsText.body(
                          size: 15,
                          weight: DsWeight.bold,
                          height: 1.2,
                          color: DsColors.textStrong,
                        ),
                      ),
                    ),
                    if (session.current) ...[
                      const SizedBox(width: DsSpace.s2),
                      DsPill(
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        background: DsColors.teal50,
                        child: Text(
                          'este',
                          style: DsText.body(
                            size: 11,
                            weight: DsWeight.bold,
                            height: 1,
                            color: DsColors.teal700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Ativo ${_relative(session.lastSeenAt)}',
                  style: DsText.body(
                    size: 12,
                    height: 1.3,
                    color: DsColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          // The current device signs out with "Sair", not from this list —
          // offering both would be two buttons for the same thing.
          if (!session.current) ...[
            const SizedBox(width: DsSpace.s2),
            DsButton(
              label: 'Desconectar',
              variant: DsButtonVariant.secondary,
              onPressed: busy ? null : onRevoke,
            ),
          ],
        ],
      ),
    );
  }

  static String _relative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 2) return 'agora';
    if (diff.inHours < 1) return 'há ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'há ${diff.inHours} h';
    if (diff.inDays == 1) return 'ontem';
    if (diff.inDays < 30) return 'há ${diff.inDays} dias';
    return 'em ${shortDayLabel(when)}';
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DsSpace.s5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: DsText.body(size: 14, height: 1.5),
            ),
            const SizedBox(height: DsSpace.s4),
            DsButton(label: 'Tentar de novo', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
