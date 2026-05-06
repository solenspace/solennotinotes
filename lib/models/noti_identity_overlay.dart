import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/theme/noti_pattern_key.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';

/// Maps a [NotiIdentity] to the [NotiThemeOverlay] that newly-created notes
/// inherit by default and that the picker opens to as a baseline.
///
/// `signaturePalette` is ordered `[background, surface, accent, onAccent]`
/// per [NotiIdentityDefaults.starterPalettes]. This extension assumes that
/// invariant; the identity factory already enforces the four-color shape.
extension NotiIdentityOverlay on NotiIdentity {
  NotiThemeOverlay toOverlay() {
    return NotiThemeOverlay(
      surface: signaturePalette[0],
      surfaceVariant: signaturePalette[1],
      accent: signaturePalette[2],
      onAccent: signaturePalette[3],
      patternKey: NotiPatternKey.fromString(signaturePatternKey),
      signatureAccent: signatureAccent,
      signatureTagline: signatureTagline,
    );
  }
}
