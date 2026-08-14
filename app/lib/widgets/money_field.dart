import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The design's boxed currency input: an "R$" prefix and a right-aligned
/// amount.
///
/// Editing is local until the user commits (submit, or moving focus away), so
/// a half-typed "1" never round-trips to the server as R$ 1,00.
class MoneyField extends StatefulWidget {
  const MoneyField({
    super.key,
    required this.valueCents,
    required this.onCommitted,
    this.width = 64,
    this.semanticLabel,
  });

  final int valueCents;

  /// Called with the parsed amount when the user finishes editing and the
  /// value actually changed.
  final ValueChanged<int> onCommitted;

  /// Width of the editable area — the surrounding box sizes to it.
  final double width;
  final String? semanticLabel;

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: formatAmount(widget.valueCents));
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(MoneyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt a value changed elsewhere (e.g. the rate was edited on another
    // screen), but never yank the text out from under an active edit.
    if (widget.valueCents != oldWidget.valueCents && !_focusNode.hasFocus) {
      _controller.text = formatAmount(widget.valueCents);
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
    final parsed = parseCents(_controller.text);
    // Unparseable or empty input reverts rather than silently becoming zero.
    if (parsed == null) {
      _controller.text = formatAmount(widget.valueCents);
      return;
    }
    _controller.text = formatAmount(parsed);
    if (parsed != widget.valueCents) widget.onCommitted(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final field = Container(
      height: DsSize.controlMd,
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s3),
      decoration: BoxDecoration(
        color: DsColors.surfaceCard,
        border: Border.all(color: DsColors.borderStrong, width: 1.5),
        borderRadius: BorderRadius.circular(DsRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            r'R$',
            style: DsText.body(
              size: 14,
              weight: DsWeight.bold,
              height: 1,
              color: DsColors.textMuted,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: widget.width,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _commit(),
              style: DsText.body(
                size: 16,
                weight: DsWeight.bold,
                height: 1,
                color: DsColors.textStrong,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '0,00',
                hintStyle: DsText.body(
                  size: 16,
                  weight: DsWeight.bold,
                  height: 1,
                  color: DsColors.slate300,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final label = widget.semanticLabel;
    return label == null
        ? field
        : Semantics(textField: true, label: label, child: field);
  }
}
