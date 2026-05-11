import 'package:flutter/material.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/curated_palettes.dart';
import 'package:noti_notes_app/theme/noti_pattern_key.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';

import 'golden_text.dart';
import 'slug.dart';
import 'themed_with.dart';

/// One row of the golden matrix: a filename-safe slug, a `ThemeData`
/// builder, and (for overlay-driven variants) the [NotiThemeOverlay] the
/// theme was built with — callers re-skin fixtures with the same overlay
/// so per-note visuals track the palette.
///
/// Themes are built lazily because `AppTheme.bone()` / `AppTheme.dark()`
/// instantiate `google_fonts` styles, which require the Flutter binding to
/// be initialized — that doesn't happen until `testWidgets`' callback runs.
class GoldenVariant {
  const GoldenVariant({
    required this.slug,
    required this.themeBuilder,
    this.overlay,
  });

  final String slug;
  final ThemeData Function() themeBuilder;
  final NotiThemeOverlay? overlay;
}

/// Base brightness + 12 curated palettes. Each palette is applied as a
/// `NotiThemeOverlay` on the dark base (the base brightness only seeds
/// state colors and ink stops under `applyToColors`).
List<GoldenVariant> palettesOnly() => <GoldenVariant>[
      GoldenVariant(
        slug: 'bone_base',
        themeBuilder: () => AppTheme.bone(text: goldenText()),
      ),
      GoldenVariant(
        slug: 'dark_base',
        themeBuilder: () => AppTheme.dark(text: goldenText(brightness: Brightness.dark)),
      ),
      for (var i = 0; i < kCuratedPalettes.length; i++)
        GoldenVariant(
          slug: paletteSlug(kCuratedPaletteNames[i]),
          themeBuilder: () => themedWith(kCuratedPalettes[i]),
          overlay: kCuratedPalettes[i],
        ),
    ];

/// Layers each of the seven [NotiPatternKey] values onto the Onyx palette
/// (the highest-contrast surface, so pattern alpha drift is most visible).
/// Used by the editor goldens to isolate the pattern channel.
List<GoldenVariant> patternsOnOnyx() {
  const onyx = NotiThemeOverlay(
    surface: Color(0xFF0F0F0F),
    surfaceVariant: Color(0xFF1A1A1A),
    accent: Color(0xFFEDEDED),
    onAccent: Color(0xFF0F0F0F),
  );
  return [
    for (final p in NotiPatternKey.values)
      GoldenVariant(
        slug: 'pattern_${p.name}',
        themeBuilder: () => themedWith(onyx.copyWith(patternKey: p)),
        overlay: onyx.copyWith(patternKey: p),
      ),
  ];
}
