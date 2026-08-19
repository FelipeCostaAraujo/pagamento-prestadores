import 'package:flutter/material.dart';

import 'tokens.dart';

/// Text styles built from the design-system type tokens.
///
/// The design doc writes CSS `font:` shorthands inline (`var(--fw-bold) 15px/1.2
/// var(--font-text)`). The two builders below are the direct equivalent, so a
/// widget reads as a transcription of the design rather than a reinterpretation
/// of it.
abstract final class DsText {
  /// Sora — headings, totals, names. Display type is always tighter-leaded.
  static TextStyle display({
    required double size,
    FontWeight weight = DsWeight.bold,
    double height = 1.15,
    Color? color,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: DsFont.display,
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color ?? DsColors.textStrong,
    letterSpacing: letterSpacing,
  );

  /// Atkinson Hyperlegible — body copy, labels, numbers, inputs.
  static TextStyle body({
    required double size,
    FontWeight weight = DsWeight.regular,
    double height = 1.5,
    Color? color,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: DsFont.text,
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color ?? DsColors.textBody,
    letterSpacing: letterSpacing,
  );

  /// Uppercase section label with wide tracking — the design system's
  /// "EM DESTAQUE" pattern.
  ///
  /// [tracking] is in `em`, matching the CSS, and is converted to the logical
  /// pixels Flutter expects.
  static TextStyle caps({
    double size = 11,
    Color? color,
    double tracking = 0.12,
  }) => body(
    size: size,
    weight: DsWeight.bold,
    height: 1,
    color: color ?? DsColors.textMuted,
    letterSpacing: size * tracking,
  );

  // Semantic roles straight from typography.css.
  static TextStyle get h1 => display(size: 36, height: 1.12);
  static TextStyle get h2 => display(size: 28, height: 1.28);
  static TextStyle get h3 =>
      display(size: 22, weight: DsWeight.semibold, height: 1.28);
  static TextStyle get bodyLg => body(size: 18, height: 1.65);
  static TextStyle get bodyMd => body(size: 16);
  static TextStyle get label =>
      body(size: 14, weight: DsWeight.bold, height: 1.28);
  static TextStyle get caption => body(size: 13);
}

abstract final class AppTheme {
  static ThemeData build() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: DsColors.brand,
      primary: DsColors.brand,
      surface: DsColors.surfaceCard,
      error: DsColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: DsColors.bgPage,
      // Atkinson Hyperlegible is the UI face; Sora is opted into per widget.
      fontFamily: DsFont.text,
      textTheme: _textTheme,
      splashFactory: InkSparkle.splashFactory,
      // The design system's focus guidance is explicit: focus indication is
      // never removed.
      focusColor: DsColors.borderFocus.withValues(alpha: 0.25),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: DsColors.brandStrong,
        selectionHandleColor: DsColors.brandStrong,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: DsColors.surfaceInverse,
        contentTextStyle: DsText.body(
          size: 13,
          weight: DsWeight.bold,
          height: 1.3,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DsRadius.md),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static TextTheme get _textTheme => TextTheme(
    displayLarge: DsText.display(
      size: 48,
      weight: DsWeight.extra,
      height: 1.12,
    ),
    headlineLarge: DsText.h1,
    headlineMedium: DsText.h2,
    headlineSmall: DsText.h3,
    titleMedium: DsText.label,
    bodyLarge: DsText.bodyLg,
    bodyMedium: DsText.bodyMd,
    bodySmall: DsText.caption,
    labelLarge: DsText.label,
  );
}
