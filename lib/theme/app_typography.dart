import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Curated fonts the user can pick in Settings. Persisted as the index of
/// the chosen value in `settings_v2[writingFont]`; do NOT remove or reorder
/// existing entries without a Hive migration. New options append at the
/// end. The actual `TextStyle` assembly per font + brightness lives in
/// `NotiText.forFont` (see `lib/theme/tokens/typography_tokens.dart`).
enum WritingFont {
  inter('Inter'),
  lora('Lora'),
  newsreader('Newsreader'),
  jetBrainsMono('JetBrains Mono'),
  sourceSerif('Source Serif 4');

  const WritingFont(this.googleFontName);

  final String googleFontName;

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
