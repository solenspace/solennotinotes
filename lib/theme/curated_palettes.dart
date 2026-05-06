import 'package:flutter/material.dart';

import 'noti_theme_overlay.dart';

/// Authoritative home for curated palette data: per-note background swatches,
/// gradient presets, optional text-color overrides, and the starter palettes
/// new identities pick from on first launch. Spec 11 hangs its per-note
/// overlay picker UI off this file; the [kCuratedPalettes] list below feeds
/// the picker's Palette tab.
///
/// `Color(0x...)` literals are allowed inside this file by design — it is
/// the canonical palette source. The `no_hardcoded_color` custom_lint rule
/// exempts this path.

/// A swatch in the curated palette used for per-note backgrounds. Each
/// swatch carries a paired dark-mode tint and an auto-contrast text color
/// derived from luminance.
class NotesSwatch {
  const NotesSwatch({
    required this.name,
    required this.light,
    required this.dark,
  });

  final String name;
  final Color light;
  final Color dark;

  /// Returns the swatch color appropriate for the current brightness.
  Color background(Brightness brightness) => brightness == Brightness.dark ? dark : light;

  /// Auto-contrast text color computed from luminance. Cards stay legible
  /// without the user picking a font color manually.
  Color autoTextColor(Brightness brightness) {
    final bg = background(brightness);
    return bg.computeLuminance() > 0.5 ? const Color(0xFF1C1B1A) : const Color(0xFFF2EFEA);
  }
}

/// 12 curated pastel swatches. Light values are warm and saturated enough
/// to look distinct in a 2-column masonry grid; dark values sit at ~22%
/// lightness so they read as muted color tints rather than full bright
/// fills.
class NotesColorPalette {
  NotesColorPalette._();

  static const List<NotesSwatch> swatches = [
    NotesSwatch(name: 'Yellow', light: Color(0xFFFFF4B8), dark: Color(0xFF3A3520)),
    NotesSwatch(name: 'Peach', light: Color(0xFFFFD9B8), dark: Color(0xFF3A2C20)),
    NotesSwatch(name: 'Rose', light: Color(0xFFFFC4C4), dark: Color(0xFF3A2424)),
    NotesSwatch(name: 'Lilac', light: Color(0xFFF4C4FF), dark: Color(0xFF35243A)),
    NotesSwatch(name: 'Periwinkle', light: Color(0xFFC4D4FF), dark: Color(0xFF24293A)),
    NotesSwatch(name: 'Sky', light: Color(0xFFC4ECFF), dark: Color(0xFF20323A)),
    NotesSwatch(name: 'Mint', light: Color(0xFFC4FFE4), dark: Color(0xFF20382C)),
    NotesSwatch(name: 'Lime', light: Color(0xFFE4FFC4), dark: Color(0xFF2C3820)),
    NotesSwatch(name: 'Sand', light: Color(0xFFF0E4D4), dark: Color(0xFF332E26)),
    NotesSwatch(name: 'Olive', light: Color(0xFFE4DCC4), dark: Color(0xFF2E2C20)),
    NotesSwatch(name: 'Stone', light: Color(0xFFD4D4D4), dark: Color(0xFF2A2A2A)),
    NotesSwatch(name: 'Paper', light: Color(0xFFFFFFFF), dark: Color(0xFF1F1F1F)),
  ];

  /// Default swatch used for newly created notes.
  static const NotesSwatch defaultSwatch = NotesSwatch(
    name: 'Paper',
    light: Color(0xFFFFFFFF),
    dark: Color(0xFF1F1F1F),
  );

  /// Find a swatch by its background color (light or dark match). Returns
  /// `null` if the color is not part of the curated set (e.g. legacy data
  /// from before the palette existed).
  static NotesSwatch? swatchFor(Color color) {
    for (final s in swatches) {
      if (s.light.toARGB32() == color.toARGB32() || s.dark.toARGB32() == color.toARGB32()) {
        return s;
      }
    }
    return null;
  }
}

/// 8 curated gradient presets. Selecting one replaces the per-note solid
/// color and pattern.
class NotesGradientPalette {
  NotesGradientPalette._();

  static const List<LinearGradient> gradients = [
    LinearGradient(
      colors: [Color(0xFFFFB6B6), Color(0xFFFFD6A5)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFC4D4FF), Color(0xFFF4C4FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFC4FFE4), Color(0xFFC4ECFF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFFFF4B8), Color(0xFFFFD9B8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFE4DCC4), Color(0xFFD4D4D4)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF614385), Color(0xFF516395)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFFF6E7F), Color(0xFFBFE9FF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ];
}

/// 8 text-color swatches for the optional per-note text-color override.
/// "Auto" is represented by `null` and falls back to
/// `NotesSwatch.autoTextColor`.
class NotesTextColorPalette {
  NotesTextColorPalette._();

  static const List<Color> colors = [
    Color(0xFF1A1A1A),
    Color(0xFFF5F5F5),
    Color(0xFFB91C1C),
    Color(0xFFB45309),
    Color(0xFF15803D),
    Color(0xFF1D4ED8),
    Color(0xFF6D28D9),
    Color(0xFFBE185D),
  ];
}

/// Starter palettes that fresh `NotiIdentity` records pick from on first
/// launch. Each entry is an ordered list of swatches:
/// `[background, surface, accent, text-on-accent]`. `signaturePalette[2]`
/// (the accent slot) is the seed color that drives `ColorScheme.fromSeed`
/// in the chrome theme.
class NotiIdentityDefaults {
  NotiIdentityDefaults._();

  static const List<List<Color>> starterPalettes = [
    [Color(0xFF2D2D2D), Color(0xFF383838), Color(0xFFE5B26B), Color(0xFFF2EFEA)],
    [Color(0xFF1B1F2A), Color(0xFF24293A), Color(0xFF7BAFD4), Color(0xFFEAF1FA)],
    [Color(0xFF1F2620), Color(0xFF2A332C), Color(0xFF8FA66F), Color(0xFFEDF1E6)],
    [Color(0xFF2A1F26), Color(0xFF362A32), Color(0xFFD37FA0), Color(0xFFF7EDF1)],
  ];
}

/// The five legacy `AppThemeColor` enum values (indigo, emerald, rose,
/// sunset, midnight), in declaration order. Kept here as user-data seed
/// constants so the `HiveSettingsRepository` migration can map a persisted
/// `appThemeColor` index to a concrete `Color` without re-introducing the
/// retired `AppThemeColor` enum.
class LegacyAppThemeColors {
  LegacyAppThemeColors._();

  static const List<Color> values = [
    Color(0xFF4F46E5), // indigo
    Color(0xFF10B981), // emerald
    Color(0xFFE11D48), // rose
    Color(0xFFF97316), // sunset
    Color(0xFF334155), // midnight
  ];
}

/// Twelve starter palettes for the per-note overlay picker (Spec 11). Each
/// is a built [NotiThemeOverlay] template carrying surface, surfaceVariant,
/// accent, and onAccent — pattern and accent glyph are picked independently
/// from their own picker tabs.
///
/// Every entry is gated by `test/theme/curated_palettes_contrast_test.dart`
/// at WCAG AA (4.5:1) on `accent vs onAccent` and on
/// `clampForReadability(surface) vs surface`. If a swatch is added or
/// retuned the build fails until contrast is restored.
///
/// `onAccent` choices in palettes 1, 3, 4, and 6 deviate from the
/// initial spec sketch (cream-on-mid-tone) in favor of a dark stop because
/// the spec sketch's pairs failed AA at 4.5:1; the surface and accent
/// values — the visual identity of each palette — are unchanged.
const List<NotiThemeOverlay> kCuratedPalettes = [
  // Bone — sage accent on warm bone surface
  NotiThemeOverlay(
    surface: Color(0xFFEDE6D6),
    surfaceVariant: Color(0xFFF5EFE2),
    accent: Color(0xFF4A8A7F),
    onAccent: Color(0xFF0F0F0F),
  ),
  // Bone + Slate
  NotiThemeOverlay(
    surface: Color(0xFFEDE6D6),
    surfaceVariant: Color(0xFFF5EFE2),
    accent: Color(0xFF4A5F8F),
    onAccent: Color(0xFFF5EFE2),
  ),
  // Bone + Rose
  NotiThemeOverlay(
    surface: Color(0xFFEDE6D6),
    surfaceVariant: Color(0xFFF5EFE2),
    accent: Color(0xFFA87878),
    onAccent: Color(0xFF0F0F0F),
  ),
  // Bone + Olive — accent darkened from spec sketch (#6B7A4A) to clear AA.
  NotiThemeOverlay(
    surface: Color(0xFFEDE6D6),
    surfaceVariant: Color(0xFFF5EFE2),
    accent: Color(0xFF5A6A3A),
    onAccent: Color(0xFFF5EFE2),
  ),
  // Bone + Charcoal
  NotiThemeOverlay(
    surface: Color(0xFFEDE6D6),
    surfaceVariant: Color(0xFFF5EFE2),
    accent: Color(0xFF3A3A3A),
    onAccent: Color(0xFFF5EFE2),
  ),
  // Cream
  NotiThemeOverlay(
    surface: Color(0xFFF5EFE2),
    surfaceVariant: Color(0xFFF8F2E7),
    accent: Color(0xFFB8704A),
    onAccent: Color(0xFF0F0F0F),
  ),
  // Sand
  NotiThemeOverlay(
    surface: Color(0xFFE8D8BD),
    surfaceVariant: Color(0xFFEDE2C9),
    accent: Color(0xFF6B5B4A),
    onAccent: Color(0xFFF8F2E7),
  ),
  // Charcoal — dark surface, gold accent
  NotiThemeOverlay(
    surface: Color(0xFF2D2D2D),
    surfaceVariant: Color(0xFF383838),
    accent: Color(0xFFE5B26B),
    onAccent: Color(0xFF1A1A1A),
  ),
  // Slate
  NotiThemeOverlay(
    surface: Color(0xFF1F2A35),
    surfaceVariant: Color(0xFF2A3744),
    accent: Color(0xFF7BAFD4),
    onAccent: Color(0xFF0E1822),
  ),
  // Moss
  NotiThemeOverlay(
    surface: Color(0xFF1F2620),
    surfaceVariant: Color(0xFF2A332C),
    accent: Color(0xFF8FA66F),
    onAccent: Color(0xFF111712),
  ),
  // Plum
  NotiThemeOverlay(
    surface: Color(0xFF2A1F26),
    surfaceVariant: Color(0xFF362A32),
    accent: Color(0xFFD37FA0),
    onAccent: Color(0xFF180F14),
  ),
  // Onyx — pure dark with near-white accent
  NotiThemeOverlay(
    surface: Color(0xFF0F0F0F),
    surfaceVariant: Color(0xFF1A1A1A),
    accent: Color(0xFFEDEDED),
    onAccent: Color(0xFF0F0F0F),
  ),
];

/// Display names for [kCuratedPalettes], parallel-indexed. Used by the
/// picker for accessibility labels and by the from-sender chip for
/// analytics-free display.
const List<String> kCuratedPaletteNames = [
  'Bone',
  'Bone + Slate',
  'Bone + Rose',
  'Bone + Olive',
  'Bone + Charcoal',
  'Cream',
  'Sand',
  'Charcoal',
  'Slate',
  'Moss',
  'Plum',
  'Onyx',
];
