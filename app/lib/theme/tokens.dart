/// Acesso+ design-system tokens, ported 1:1 from the design project's
/// `_ds/.../tokens/*.css`.
///
/// The CSS is the source of truth: when a token changes there, change it here
/// and nowhere else. Widgets must reference the semantic aliases
/// ([DsColors.textStrong], [DsColors.surfaceCard], …) rather than raw ramp
/// entries, exactly as the CSS guidance requires.
library;

import 'package:flutter/widgets.dart';

// ---------------------------------------------------------------- colors --

abstract final class DsColors {
  // Brand ramp (teal -> ocean -> deep).
  static const teal50 = Color(0xFFECFBF8);
  static const teal100 = Color(0xFFCDF3EC);
  static const teal200 = Color(0xFF9DE7DB);
  static const teal300 = Color(0xFF62D3C3);
  static const teal400 = Color(0xFF2FBDAC);

  /// Primary brand teal.
  static const teal500 = Color(0xFF18A498);
  static const teal600 = Color(0xFF0F8479);
  static const teal700 = Color(0xFF11675F);
  static const teal800 = Color(0xFF0F514C);
  static const teal900 = Color(0xFF0C3B38);

  static const ocean400 = Color(0xFF3793A8);
  static const ocean500 = Color(0xFF1E6E8C);
  static const ocean600 = Color(0xFF1A5670);
  static const ocean700 = Color(0xFF173F54);

  /// Deepest brand ink.
  static const navy900 = Color(0xFF0E2D3A);

  // Neutral slate ramp.
  static const slate0 = Color(0xFFFFFFFF);
  static const slate50 = Color(0xFFF6F8F9);
  static const slate100 = Color(0xFFECF0F2);
  static const slate200 = Color(0xFFDCE3E6);
  static const slate300 = Color(0xFFC2CDD2);
  static const slate400 = Color(0xFF94A4AB);
  static const slate500 = Color(0xFF6B7C84);
  static const slate600 = Color(0xFF4E5D64);
  static const slate700 = Color(0xFF38454B);
  static const slate800 = Color(0xFF253035);
  static const slate900 = Color(0xFF141C20);

  // Functional / semantic.
  static const success = Color(0xFF168F52);
  static const warning = Color(0xFFE2A00A);
  static const danger = Color(0xFFD43F3A);
  static const info = ocean500;

  // Semantic aliases — prefer these in widgets.
  static const brand = teal500;
  static const brandStrong = teal600;
  static const brandInk = navy900;

  static const bgPage = slate50;
  static const bgPageStrong = slate100;
  static const surfaceCard = slate0;
  static const surfaceSunken = slate50;
  static const surfaceInverse = navy900;

  static const textStrong = slate900;
  static const textBody = slate700;
  static const textMuted = slate500;
  static const textOnBrand = Color(0xFFFFFFFF);
  static const textLink = teal600;

  static const borderSubtle = slate200;
  static const borderStrong = slate300;
  static const borderFocus = teal500;

  /// `--overlay-scrim`: navy at 55%.
  static const overlayScrim = Color(0x8C0E2D3A);

  // Status pill colours for the Fechamento cards. The design doc hard-codes
  // these alongside the token set.
  static const paidFg = success;
  static const paidBg = Color(0xFFDEF3E7);
  static const openFg = Color(0xFF8A6000);
  static const openBg = Color(0xFFFBEFCB);

  // WhatsApp-style message preview in the share dialog.
  static const messageBg = Color(0xFFE7FCE3);
  static const messageBorder = Color(0xFFC4EFBB);
}

/// Gradients (`--grad-*`).
abstract final class DsGradients {
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2FBDAC), Color(0xFF18A498), Color(0xFF1E6E8C)],
    stops: [0.0, 0.38, 1.0],
  );

  static const brandSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFECFBF8), Color(0xFFE5F1F4)],
  );

  /// `--grad-hero`: 160deg, used by the app header.
  ///
  /// CSS 160deg runs top-ish to bottom-ish, tilted slightly right; the
  /// alignment pair below is the equivalent for a tall header box.
  static const hero = LinearGradient(
    begin: Alignment(-0.34, -1.0),
    end: Alignment(0.34, 1.0),
    colors: [Color(0xFF11675F), Color(0xFF173F54)],
  );
}

/// The prestadora palette.
///
/// The design reuses the design system's four accessibility-category colours as
/// per-person identity colours. Order matters: it is the order the backend's
/// `color_index` refers to, and it matches `PALETTE` in the design doc
/// (física, auditiva, visual, sensorial). Each hue differs in lightness as well
/// as hue so the calendar dots stay distinguishable for colour-vision-deficient
/// users — and the app always pairs colour with the person's name.
abstract final class DsPalette {
  static const entries = <ProviderColor>[
    ProviderColor(dot: Color(0xFF2563EB), tint: Color(0xFFE5EDFE)), // física
    ProviderColor(dot: Color(0xFFE26B0A), tint: Color(0xFFFCEBDB)), // auditiva
    ProviderColor(dot: Color(0xFF8B3FE0), tint: Color(0xFFF0E7FC)), // visual
    ProviderColor(dot: Color(0xFF168F52), tint: Color(0xFFDEF3E7)), // sensorial
  ];

  static int get length => entries.length;

  /// Wraps out-of-range indexes so an unexpected value from the API can never
  /// crash the calendar.
  static ProviderColor at(int index) =>
      entries[index.abs() % entries.length];
}

@immutable
class ProviderColor {
  const ProviderColor({required this.dot, required this.tint});

  /// Saturated colour: dots, name accents, checked states.
  final Color dot;

  /// Pale companion for filled backgrounds.
  final Color tint;
}

// ------------------------------------------------------- spacing / radius --

/// `tokens/spacing.css` — 8px base grid.
abstract final class DsSpace {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 24.0;
  static const s6 = 32.0;
  static const s7 = 40.0;
  static const s8 = 48.0;
  static const s9 = 64.0;
  static const s10 = 80.0;
}

abstract final class DsRadius {
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;

  /// `--radius-pill`.
  static const pill = 999.0;
}

/// Minimum interactive sizing. 44px is a hard accessibility floor in this
/// design system (`--touch-min`) — do not shrink controls below it.
abstract final class DsSize {
  static const touchMin = 44.0;
  static const controlSm = 36.0;
  static const controlMd = 44.0;
  static const controlLg = 52.0;
}

// ---------------------------------------------------------------- effects --

/// `tokens/effects.css` — navy-tinted elevation so shadows read as part of the
/// brand rather than as neutral grey.
abstract final class DsShadows {
  static const _tint = Color(0xFF0E2D3A);

  static List<BoxShadow> get xs => [
    BoxShadow(
      color: _tint.withValues(alpha: 0.06),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get sm => [
    BoxShadow(
      color: _tint.withValues(alpha: 0.08),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get md => [
    BoxShadow(
      color: _tint.withValues(alpha: 0.10),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> get lg => [
    BoxShadow(
      color: _tint.withValues(alpha: 0.14),
      blurRadius: 36,
      offset: const Offset(0, 14),
    ),
  ];

  static List<BoxShadow> get xl => [
    BoxShadow(
      color: _tint.withValues(alpha: 0.18),
      blurRadius: 60,
      offset: const Offset(0, 24),
    ),
  ];

  /// Teal glow reserved for primary brand buttons.
  static List<BoxShadow> get brand => [
    BoxShadow(
      color: DsColors.teal500.withValues(alpha: 0.30),
      blurRadius: 26,
      offset: const Offset(0, 10),
    ),
  ];

  /// `--shadow-card` aliases `--shadow-sm`.
  static List<BoxShadow> get card => sm;
}

/// Motion tokens — calm, no overshoot.
abstract final class DsMotion {
  static const easeOut = Cubic(0.22, 1, 0.36, 1);
  static const easeInOut = Cubic(0.65, 0, 0.35, 1);
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
}

// ------------------------------------------------------------- typography --

/// `tokens/typography.css`. Display = Sora, Text/UI = Atkinson Hyperlegible.
abstract final class DsFont {
  static const display = 'Sora';
  static const text = 'AtkinsonHyperlegible';
}

/// Font weights (`--fw-*`).
abstract final class DsWeight {
  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
  static const bold = FontWeight.w700;
  static const extra = FontWeight.w800;
}
