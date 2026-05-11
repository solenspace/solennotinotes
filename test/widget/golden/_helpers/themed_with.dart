import 'package:flutter/material.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';
import 'package:noti_notes_app/theme/tokens.dart';

import 'golden_text.dart';

/// Composes a `ThemeData` from a base brightness + a [NotiThemeOverlay] by
/// patching the eight registered token extensions exactly the way the three
/// production sites do (note_editor/screen.dart, share_nearby_sheet.dart,
/// share_preview_panel.dart). Lives in test-only space because production
/// never builds a themed surface without a `BuildContext`.
ThemeData themedWith(NotiThemeOverlay overlay, {Brightness base = Brightness.dark}) {
  final root = base == Brightness.dark
      ? AppTheme.dark(text: goldenText(brightness: Brightness.dark))
      : AppTheme.bone(text: goldenText(brightness: Brightness.light));
  final tokens = _tokensOf(root);
  return root.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      overlay.applyToColors(tokens.colors),
      tokens.text,
      tokens.motion,
      tokens.shape,
      tokens.elevation,
      tokens.spacing,
      overlay.applyToPatternBackdrop(tokens.patternBackdrop),
      overlay.applyToSignature(tokens.signature),
    ],
  );
}

Tokens _tokensOf(ThemeData theme) {
  return Tokens(
    colors: theme.extension<NotiColors>()!,
    text: theme.extension<NotiText>()!,
    motion: theme.extension<NotiMotion>()!,
    shape: theme.extension<NotiShape>()!,
    elevation: theme.extension<NotiElevation>()!,
    spacing: theme.extension<NotiSpacing>()!,
    patternBackdrop: theme.extension<NotiPatternBackdrop>()!,
    signature: theme.extension<NotiSignature>()!,
  );
}
