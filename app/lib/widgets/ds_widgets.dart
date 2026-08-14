import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Button variants from the Acesso+ core component set.
enum DsButtonVariant { primary, secondary, ghost }

enum DsButtonSize { md, lg }

/// `AcessoDesignSystem.Button`.
///
/// Primary carries the teal fill and brand glow; secondary is a hairline
/// outline on white; ghost is chrome-free. All three press with the design
/// system's `scale(0.97)` — deliberately no bounce.
class DsButton extends StatefulWidget {
  const DsButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = DsButtonVariant.primary,
    this.size = DsButtonSize.md,
    this.block = false,
  });

  final String label;

  /// A null callback renders the disabled state.
  final VoidCallback? onPressed;
  final DsButtonVariant variant;
  final DsButtonSize size;

  /// Stretch to the available width.
  final bool block;

  @override
  State<DsButton> createState() => _DsButtonState();
}

class _DsButtonState extends State<DsButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  double get _height => switch (widget.size) {
    DsButtonSize.md => DsSize.controlMd + 4, // 48px, per the design doc
    DsButtonSize.lg => DsSize.controlLg,
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = _colors();

    final button = AnimatedScale(
      scale: _pressed && _enabled ? 0.97 : 1,
      duration: DsMotion.fast,
      curve: DsMotion.easeOut,
      child: AnimatedContainer(
        duration: DsMotion.fast,
        curve: DsMotion.easeOut,
        height: _height,
        padding: EdgeInsets.symmetric(
          horizontal: widget.size == DsButtonSize.lg ? DsSpace.s5 : DsSpace.s4,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(DsRadius.md),
          border: border == null ? null : Border.all(color: border, width: 1.5),
          // The teal glow is reserved for the enabled primary action.
          boxShadow:
              widget.variant == DsButtonVariant.primary && _enabled && !_pressed
              ? DsShadows.brand
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DsText.body(
            size: widget.size == DsButtonSize.lg ? 16 : 15,
            weight: DsWeight.bold,
            height: 1,
            color: fg,
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: MouseRegion(
          cursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
          child: widget.block
              ? SizedBox(width: double.infinity, child: button)
              : button,
        ),
      ),
    );
  }

  /// Returns (background, foreground, border) for the current variant/state.
  (Color, Color, Color?) _colors() {
    if (!_enabled) {
      return (DsColors.slate100, DsColors.slate400, null);
    }
    return switch (widget.variant) {
      DsButtonVariant.primary => (
        _pressed ? DsColors.teal600 : DsColors.brand,
        DsColors.textOnBrand,
        null,
      ),
      DsButtonVariant.secondary => (
        _pressed ? DsColors.slate50 : DsColors.surfaceCard,
        DsColors.textBody,
        DsColors.borderStrong,
      ),
      DsButtonVariant.ghost => (
        _pressed ? DsColors.slate100 : Colors.transparent,
        DsColors.textLink,
        null,
      ),
    };
  }
}

/// `AcessoDesignSystem.Avatar` — initials on a solid disc.
///
/// [color] lets the Fechamento card tint the avatar with the prestadora's own
/// palette colour so the card ties back to her calendar dots; it falls back to
/// the brand gradient.
class DsAvatar extends StatelessWidget {
  const DsAvatar({super.key, required this.name, this.size = 42, this.color});

  final String name;
  final double size;
  final Color? color;

  /// First letters of the first and last words — "Marina Souza" -> "MS".
  static String initialsFor(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.characters.first.toUpperCase();
    return (words.first.characters.first + words.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        gradient: color == null ? DsGradients.brand : null,
      ),
      child: Text(
        initialsFor(name),
        style: DsText.display(
          // Keeps the initials optically centred at any avatar size.
          size: size * 0.38,
          weight: DsWeight.bold,
          height: 1,
          color: DsColors.textOnBrand,
        ),
      ),
    );
  }
}

/// The design system's card: white surface, hairline border, navy-tinted
/// shadow, 20px radius.
class DsCard extends StatelessWidget {
  const DsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DsSpace.s4),
    this.radius = DsRadius.lg,
    this.elevated = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// List rows in the design use the same surface without the shadow.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: DsColors.surfaceCard,
        border: Border.all(color: DsColors.borderSubtle),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: elevated ? DsShadows.card : null,
      ),
      child: child,
    );
  }
}

/// Pill-shaped chip used for the calendar legend, the day list and status
/// badges.
class DsPill extends StatelessWidget {
  const DsPill({
    super.key,
    required this.child,
    required this.background,
    this.border,
    this.height = 30,
    this.padding = const EdgeInsets.symmetric(horizontal: DsSpace.s3),
  });

  final Widget child;
  final Color background;
  final Color? border;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(DsRadius.pill),
        border: border == null ? null : Border.all(color: border!),
      ),
      // No `alignment` here: giving Container an alignment makes it expand to
      // the full available width, and these are inline-flex chips in the design
      // that must hug their content. The fixed height already centres the
      // child vertically.
      child: child,
    );
  }
}

/// A small round colour dot — the calendar's "who worked" marker.
class DsDot extends StatelessWidget {
  const DsDot({super.key, required this.color, this.size = 6});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
