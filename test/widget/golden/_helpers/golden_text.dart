import 'package:flutter/material.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens/typography_tokens.dart';

/// Blank-styled [NotiText] for goldens. Production reads Inter via
/// `google_fonts`, which tries to fetch the family over the network at
/// runtime — a non-starter in `flutter test` (no network) and a non-starter
/// in this project at all (offline invariant). Goldens substitute a fully
/// inert [NotiText]; text renders in Flutter's default Ahem font, which is
/// pixel-deterministic across hosts.
///
/// Mirrors the `_stubText()` helper already in
/// `test/features/inbox/widgets/share_preview_panel_test.dart`.
NotiText goldenText({Brightness brightness = Brightness.light}) {
  const blank = TextStyle();
  return NotiText(
    writingFont: WritingFont.inter,
    brightness: brightness,
    displayLg: blank,
    displayMd: blank,
    displaySm: blank,
    headlineMd: blank,
    titleLg: blank,
    titleMd: blank,
    titleSm: blank,
    bodyLg: blank,
    bodyMd: blank,
    bodySm: blank,
    labelLg: blank,
    labelMd: blank,
    labelSm: blank,
  );
}
