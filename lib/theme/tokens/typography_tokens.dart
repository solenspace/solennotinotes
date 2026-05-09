import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens/color_tokens.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';

/// Typography role bundle. The same M3 type-scale roles the existing
/// `AppTypography.buildTextTheme` produced, packaged as a `ThemeExtension`
/// so widgets can read styles via `context.tokens.text.bodyLg` without
/// going through `Theme.of(context).textTheme.bodyLarge!`.
@immutable
class NotiText extends ThemeExtension<NotiText> {
  const NotiText({
    required this.writingFont,
    required this.brightness,
    required this.displayLg,
    required this.displayMd,
    required this.displaySm,
    required this.headlineMd,
    required this.titleLg,
    required this.titleMd,
    required this.titleSm,
    required this.bodyLg,
    required this.bodyMd,
    required this.bodySm,
    required this.labelLg,
    required this.labelMd,
    required this.labelSm,
  });

  /// The font selection that produced this NotiText. Captured so
  /// `app_theme.dart` can wire `ThemeData.fontFamily` consistently.
  final WritingFont writingFont;
  final Brightness brightness;

  final TextStyle displayLg;
  final TextStyle displayMd;
  final TextStyle displaySm;
  final TextStyle headlineMd;
  final TextStyle titleLg;
  final TextStyle titleMd;
  final TextStyle titleSm;
  final TextStyle bodyLg;
  final TextStyle bodyMd;
  final TextStyle bodySm;
  final TextStyle labelLg;
  final TextStyle labelMd;
  final TextStyle labelSm;

  /// Builds the role bundle for a given writing font + brightness, porting
  /// the legacy `AppTypography.buildTextTheme` logic (including the
  /// monospace letter-spacing / line-height tweaks for JetBrains Mono).
  factory NotiText.forFont(WritingFont font, Brightness brightness) {
    final onSurface =
        brightness == Brightness.dark ? NotiColors.dark.onSurface : NotiColors.bone.onSurface;
    final onSurfaceMuted = brightness == Brightness.dark
        ? NotiColors.dark.onSurfaceMuted
        : NotiColors.bone.onSurfaceMuted;

    final isMonospace = font == WritingFont.jetBrainsMono;
    final double? monoLetterSpacing = isMonospace ? 0.0 : null;
    final double monoHeightMultiplier = isMonospace ? 1.2 : 1.0;

    TextStyle style({
      required double fontSize,
      required double height,
      required FontWeight fontWeight,
      required Color color,
      double? letterSpacing,
    }) {
      return GoogleFonts.getFont(
        font.googleFontName,
        fontSize: fontSize,
        height: height,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
      );
    }

    return NotiText(
      writingFont: font,
      brightness: brightness,
      displayLg: style(
        fontSize: 28,
        height: 34 / 28,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: isMonospace ? monoLetterSpacing : -0.5,
      ),
      displayMd: style(
        fontSize: 24,
        height: 30 / 24,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: isMonospace ? monoLetterSpacing : -0.3,
      ),
      displaySm: style(
        fontSize: TextSizePrimitives.titleLg,
        height: 24 / 18,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: monoLetterSpacing,
      ),
      headlineMd: style(
        fontSize: TextSizePrimitives.bodyMd,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        color: onSurface,
        letterSpacing: monoLetterSpacing,
      ),
      titleLg: style(
        fontSize: TextSizePrimitives.headlineMd,
        height: 26 / 20,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: monoLetterSpacing,
      ),
      titleMd: style(
        fontSize: TextSizePrimitives.titleMd,
        height: 22 / 17,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: monoLetterSpacing,
      ),
      titleSm: style(
        fontSize: TextSizePrimitives.titleSm,
        height: 20 / 15,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: monoLetterSpacing,
      ),
      bodyLg: style(
        fontSize: TextSizePrimitives.bodyLg,
        height: (25 / 17) * monoHeightMultiplier,
        fontWeight: FontWeight.w400,
        color: onSurface,
        letterSpacing: monoLetterSpacing,
      ),
      bodyMd: style(
        fontSize: TextSizePrimitives.bodySm,
        height: (19 / 13) * monoHeightMultiplier,
        fontWeight: FontWeight.w400,
        color: onSurfaceMuted,
        letterSpacing: monoLetterSpacing,
      ),
      bodySm: style(
        fontSize: 12,
        height: (16 / 12) * monoHeightMultiplier,
        fontWeight: FontWeight.w400,
        color: onSurfaceMuted,
        letterSpacing: monoLetterSpacing,
      ),
      labelLg: style(
        fontSize: TextSizePrimitives.labelLg,
        height: (18 / 14) * monoHeightMultiplier,
        fontWeight: FontWeight.w500,
        color: onSurface,
        letterSpacing: monoLetterSpacing,
      ),
      labelMd: style(
        fontSize: TextSizePrimitives.labelMd,
        height: (18 / 13) * monoHeightMultiplier,
        fontWeight: FontWeight.w500,
        color: onSurface,
        letterSpacing: monoLetterSpacing,
      ),
      labelSm: style(
        fontSize: TextSizePrimitives.labelSm,
        height: (14 / 11) * monoHeightMultiplier,
        fontWeight: FontWeight.w500,
        color: onSurfaceMuted,
        letterSpacing: isMonospace ? monoLetterSpacing : 0.4,
      ),
    );
  }

  /// Builds a Material `TextTheme` from this role bundle so
  /// `ThemeData.textTheme` keeps working for all the framework widgets that
  /// read `Theme.of(context).textTheme.titleLarge` etc.
  TextTheme toTextTheme() => TextTheme(
        displayLarge: displayLg,
        displayMedium: displayMd,
        displaySmall: displaySm,
        headlineMedium: headlineMd,
        titleLarge: titleLg,
        titleMedium: titleMd,
        titleSmall: titleSm,
        bodyLarge: bodyLg,
        bodyMedium: bodyMd,
        bodySmall: bodySm,
        labelLarge: labelLg,
        labelMedium: labelMd,
        labelSmall: labelSm,
      );

  @override
  NotiText copyWith({
    WritingFont? writingFont,
    Brightness? brightness,
    TextStyle? displayLg,
    TextStyle? displayMd,
    TextStyle? displaySm,
    TextStyle? headlineMd,
    TextStyle? titleLg,
    TextStyle? titleMd,
    TextStyle? titleSm,
    TextStyle? bodyLg,
    TextStyle? bodyMd,
    TextStyle? bodySm,
    TextStyle? labelLg,
    TextStyle? labelMd,
    TextStyle? labelSm,
  }) {
    return NotiText(
      writingFont: writingFont ?? this.writingFont,
      brightness: brightness ?? this.brightness,
      displayLg: displayLg ?? this.displayLg,
      displayMd: displayMd ?? this.displayMd,
      displaySm: displaySm ?? this.displaySm,
      headlineMd: headlineMd ?? this.headlineMd,
      titleLg: titleLg ?? this.titleLg,
      titleMd: titleMd ?? this.titleMd,
      titleSm: titleSm ?? this.titleSm,
      bodyLg: bodyLg ?? this.bodyLg,
      bodyMd: bodyMd ?? this.bodyMd,
      bodySm: bodySm ?? this.bodySm,
      labelLg: labelLg ?? this.labelLg,
      labelMd: labelMd ?? this.labelMd,
      labelSm: labelSm ?? this.labelSm,
    );
  }

  @override
  NotiText lerp(ThemeExtension<NotiText>? other, double t) {
    if (other is! NotiText) return this;
    return NotiText(
      writingFont: t < 0.5 ? writingFont : other.writingFont,
      brightness: t < 0.5 ? brightness : other.brightness,
      displayLg: TextStyle.lerp(displayLg, other.displayLg, t)!,
      displayMd: TextStyle.lerp(displayMd, other.displayMd, t)!,
      displaySm: TextStyle.lerp(displaySm, other.displaySm, t)!,
      headlineMd: TextStyle.lerp(headlineMd, other.headlineMd, t)!,
      titleLg: TextStyle.lerp(titleLg, other.titleLg, t)!,
      titleMd: TextStyle.lerp(titleMd, other.titleMd, t)!,
      titleSm: TextStyle.lerp(titleSm, other.titleSm, t)!,
      bodyLg: TextStyle.lerp(bodyLg, other.bodyLg, t)!,
      bodyMd: TextStyle.lerp(bodyMd, other.bodyMd, t)!,
      bodySm: TextStyle.lerp(bodySm, other.bodySm, t)!,
      labelLg: TextStyle.lerp(labelLg, other.labelLg, t)!,
      labelMd: TextStyle.lerp(labelMd, other.labelMd, t)!,
      labelSm: TextStyle.lerp(labelSm, other.labelSm, t)!,
    );
  }
}
