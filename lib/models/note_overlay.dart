import 'package:flutter/painting.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/theme/noti_pattern_key.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';

/// Bridges the legacy [Note] schema to the [NotiThemeOverlay] model.
///
/// Spec 11 keeps the scattered overlay fields (`colorBackground`,
/// `fontColor`, `patternImage`, `gradient`, `hasGradient`) on `Note` for
/// Hive-storage compatibility — every overlay event handler writes through
/// to these columns, and every editor render synthesizes its overlay via
/// this extension. Spec 04b retires the legacy fields in favor of a single
/// `Note.overlay: NotiThemeOverlay` value.
///
/// `signatureAccent`, `signatureTagline`, and `fromIdentityId` are not
/// stored on the legacy schema, so they remain null/empty until 04b.
extension NoteOverlay on Note {
  NotiThemeOverlay toOverlay() {
    final hasUsableGradient = hasGradient && gradient != null && gradient!.colors.isNotEmpty;
    return NotiThemeOverlay(
      surface: colorBackground,
      surfaceVariant: Color.lerp(colorBackground, fontColor, 0.08)!,
      accent:
          hasUsableGradient ? gradient!.colors.last : Color.lerp(colorBackground, fontColor, 0.6)!,
      onAccent: colorBackground,
      onSurface: fontColor,
      patternKey: NotiPatternKey.fromString(patternImage),
    );
  }
}
