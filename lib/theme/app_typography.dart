import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Curated fonts the user can pick in Settings.
/// This font will be applied harmonically across the entire application UI.
enum WritingFont {
  inter('Inter'),
  lora('Lora'),
  newsreader('Newsreader'),
  jetBrainsMono('JetBrains Mono'),
  sourceSerif('Source Serif 4');

  final String googleFontName;
  const WritingFont(this.googleFontName);

  String get displayName {
    switch (this) {
      case WritingFont.inter:
        return 'Inter';
      case WritingFont.lora:
        return 'Lora';
      case WritingFont.newsreader:
        return 'Newsreader';
      case WritingFont.jetBrainsMono:
        return 'JetBrains Mono';
      case WritingFont.sourceSerif:
        return 'Source Serif';
    }
  }

  TextStyle get sample => GoogleFonts.getFont(googleFontName);
}

/// Builds the app TextTheme using a chosen font for all UI elements.
/// Applies the selected font harmonically across display, title, body, and label styles.
/// Special handling for monospace fonts to ensure proper spacing and readability.
class AppTypography {
  AppTypography._();

  static TextTheme buildTextTheme({
    required Brightness brightness,
    required WritingFont writingFont,
  }) {
    final onSurface =
        brightness == Brightness.dark ? Colors.white : const Color(0xFF1A1A1A);
    final onSurfaceMuted = onSurface.withValues(alpha: 0.6);

    // Check if the selected font is monospace (JetBrains Mono)
    final isMonospace = writingFont == WritingFont.jetBrainsMono;
    
    // Adjustments for monospace fonts to ensure proper readability in UI contexts
    final double? monospaceLetterSpacing = isMonospace ? 0.0 : null;
    final double monospaceHeightMultiplier = isMonospace ? 1.2 : 1.0;

    // Helper to easily get a text style with the selected font
    TextStyle fontStyle({
      required double fontSize,
      required double height,
      required FontWeight fontWeight,
      required Color color,
      double? letterSpacing,
    }) {
      return GoogleFonts.getFont(
        writingFont.googleFontName,
        fontSize: fontSize,
        height: height,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
      );
    }

    return TextTheme(
      // Editor title
      displayLarge: fontStyle(
        fontSize: 28,
        height: 34 / 28,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: isMonospace ? monospaceLetterSpacing : -0.5,
      ),
      displayMedium: fontStyle(
        fontSize: 24,
        height: 30 / 24,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: isMonospace ? monospaceLetterSpacing : -0.3,
      ),
      displaySmall: fontStyle(
        fontSize: 18,
        height: 24 / 18,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: isMonospace ? monospaceLetterSpacing : null,
      ),
      headlineMedium: fontStyle(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w400,
        color: onSurface,
        letterSpacing: isMonospace ? monospaceLetterSpacing : null,
      ),
      // Sheet headings, app bar
      titleLarge: fontStyle(
        fontSize: 20,
        height: 26 / 20,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: isMonospace ? monospaceLetterSpacing : null,
      ),
      titleMedium: fontStyle(
        fontSize: 17,
        height: 22 / 17,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: isMonospace ? monospaceLetterSpacing : null,
      ),
      // Card title (semibold)
      titleSmall: fontStyle(
        fontSize: 15,
        height: 20 / 15,
        fontWeight: FontWeight.w600,
        color: onSurface,
        letterSpacing: isMonospace ? monospaceLetterSpacing : null,
      ),
      // Editor body
      bodyLarge: fontStyle(
        fontSize: 17,
        height: (25 / 17) * monospaceHeightMultiplier,
        fontWeight: FontWeight.w400,
        color: onSurface,
        letterSpacing: isMonospace ? monospaceLetterSpacing : null,
      ),
      // Card preview, todos
      bodyMedium: fontStyle(
        fontSize: 13,
        height: (19 / 13) * monospaceHeightMultiplier,
        fontWeight: FontWeight.w400,
        color: onSurfaceMuted,
        letterSpacing: isMonospace ? monospaceLetterSpacing : null,
      ),
      bodySmall: fontStyle(
        fontSize: 12,
        height: (16 / 12) * monospaceHeightMultiplier,
        fontWeight: FontWeight.w400,
        color: onSurfaceMuted,
        letterSpacing: isMonospace ? monospaceLetterSpacing : null,
      ),
      // Chips, metadata
      labelLarge: fontStyle(
        fontSize: 14,
        height: (18 / 14) * monospaceHeightMultiplier,
        fontWeight: FontWeight.w500,
        color: onSurface,
        letterSpacing: isMonospace ? monospaceLetterSpacing : null,
      ),
      labelMedium: fontStyle(
        fontSize: 13,
        height: (18 / 13) * monospaceHeightMultiplier,
        fontWeight: FontWeight.w500,
        color: onSurface,
        letterSpacing: isMonospace ? monospaceLetterSpacing : null,
      ),
      labelSmall: fontStyle(
        fontSize: 11,
        height: (14 / 11) * monospaceHeightMultiplier,
        fontWeight: FontWeight.w500,
        color: onSurfaceMuted,
        letterSpacing: isMonospace ? monospaceLetterSpacing : 0.4,
      ),
    );
  }
}
