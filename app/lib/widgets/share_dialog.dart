import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
              'Para ${closing.provider.displayName}, por WhatsApp',
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
                    label: 'Copiar mensagem',
                    block: true,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: message));
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      state.showToast(
                        'Mensagem de ${closing.provider.firstName} copiada',
                      );
                    },
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
          ],
        ),
      ),
    );
  }
}
