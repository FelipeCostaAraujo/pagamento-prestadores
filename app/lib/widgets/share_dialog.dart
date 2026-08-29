import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'ds_widgets.dart';

/// Builds the WhatsApp message for a prestadora's month, exactly as the design
/// previews it.
String closingMessage(ProviderClosing closing, int month) {
  final diarias = closing.entryCount == 1
      ? '1 diária'
      : '${closing.entryCount} diárias';
  return 'Oi, ${closing.provider.firstName}! '
      'Fechamento de ${monthName(month)}:\n'
      '$diarias · total ${formatMoney(closing.totalCents)}.\n'
      'Posso pagar hoje?';
}

/// Shows the message before it goes anywhere — the design is explicit that the
/// user reads the text first.
Future<void> showShareDialog(
  BuildContext context, {
  required AppState state,
  required ProviderClosing closing,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: DsColors.overlayScrim,
    builder: (_) => _ShareDialog(state: state, closing: closing),
  );
}

class _ShareDialog extends StatelessWidget {
  const _ShareDialog({required this.state, required this.closing});

  final AppState state;
  final ProviderClosing closing;

  /// Opens the WhatsApp conversation with the message ready to send.
  ///
  /// Deliberately stops at "ready to send": the app composes, the user presses
  /// send. Nothing leaves the phone without her seeing it.
  ///
  /// Falls back to the clipboard whenever the hand-off cannot happen — no
  /// number, an unusable number, or no WhatsApp installed — so the button
  /// always accomplishes something.
  Future<void> _send(BuildContext context, String message) async {
    final number = closing.provider.whatsappNumber;
    final firstName = closing.provider.firstName;

    if (number != null) {
      final text = Uri.encodeComponent(message);
      // The app scheme first, then the web link. Both end in the same place,
      // but wa.me on a phone whose default browser claims https opens the
      // browser and makes the user tap through — verified on the S20.
      final targets = [
        Uri.parse('whatsapp://send?phone=$number&text=$text'),
        Uri.parse('https://wa.me/$number?text=$text'),
      ];

      for (final uri in targets) {
        try {
          if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            if (!context.mounted) return;
            Navigator.of(context).pop();
            return;
          }
        } catch (_) {
          // Not installed, or no handler — try the next one.
        }
      }
    }

    await Clipboard.setData(ClipboardData(text: message));
    if (!context.mounted) return;
    Navigator.of(context).pop();
    state.showToast(
      number == null
          ? 'Mensagem de $firstName copiada'
          : 'Não consegui abrir o WhatsApp; mensagem copiada',
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = closingMessage(closing, state.month);

    return Dialog(
      backgroundColor: DsColors.surfaceCard,
      insetPadding: const EdgeInsets.all(DsSpace.s5),
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
              'Enviar fechamento',
              style: DsText.display(size: 18, height: 1.2),
            ),
            const SizedBox(height: 6),
            Text(
              closing.provider.hasPhone
                  ? 'Para ${closing.provider.displayName} · ${closing.provider.phone}'
                  : 'Para ${closing.provider.displayName} — sem número cadastrado',
              style: DsText.body(
                size: 13,
                height: 1.4,
                color: DsColors.textMuted,
              ),
            ),
            const SizedBox(height: DsSpace.s4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DsColors.messageBg,
                border: Border.all(color: DsColors.messageBorder),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                message,
                style: DsText.body(
                  size: 13,
                  height: 1.55,
                  color: DsColors.slate800,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: DsButton(
                    // Without a number there is nothing to open, so the button
                    // says what it will actually do instead of failing later.
                    label: closing.provider.hasPhone
                        ? 'Abrir no WhatsApp'
                        : 'Copiar mensagem',
                    block: true,
                    onPressed: () => _send(context, message),
                  ),
                ),
                const SizedBox(width: DsSpace.s2),
                DsButton(
                  label: 'Cancelar',
                  variant: DsButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            if (!closing.provider.hasPhone) ...[
              const SizedBox(height: DsSpace.s3),
              Text(
                'Cadastre o WhatsApp dela na aba Prestadoras para abrir a '
                'conversa direto.',
                textAlign: TextAlign.center,
                style: DsText.body(
                  size: 12,
                  height: 1.4,
                  color: DsColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
