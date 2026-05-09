import 'package:flutter/material.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';

/// Tot-style signature mark on a home note card. Renders a 12px accent dot
/// for notes without a custom glyph; renders the glyph itself in the
/// overlay's accent color when one is set.
///
/// The widget reads from the synthesized [NotiThemeOverlay] (via
/// `note.toOverlay()`), so legacy fields and future Spec-04b-promoted
/// fields converge on the same render path.
class NoteOverlayDot extends StatelessWidget {
  const NoteOverlayDot({super.key, required this.overlay});

  final NotiThemeOverlay overlay;

  @override
  Widget build(BuildContext context) {
    final glyph = overlay.signatureAccent;
    if (glyph != null) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Text(
          glyph,
          style: TextStyle(color: overlay.accent, fontSize: 14),
        ),
      );
    }
    return Container(
      width: 12,
      height: 12,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: overlay.accent,
        shape: BoxShape.circle,
      ),
    );
  }
}
