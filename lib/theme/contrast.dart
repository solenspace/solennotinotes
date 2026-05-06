import 'package:flutter/painting.dart';

import 'tokens/primitives.dart';

/// WCAG 2.x relative-luminance contrast helpers.
///
/// Spec 11 layers four readability defenses on top of curated palettes; this
/// file is the runtime gate for two of them: build-time validation of the
/// curated palette set, and runtime fallback for the custom HSL picker.
///
/// We use Flutter's built-in [Color.computeLuminance] (sRGB-linearized per
/// WCAG) rather than reimplementing the channel math — same numbers, fewer
/// places to drift.

/// WCAG 2.x contrast ratio: `(L1 + 0.05) / (L2 + 0.05)` with L1 = lighter,
/// L2 = darker. Returns a value in the closed range `[1.0, 21.0]`.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// AA gate for body text (≥ 4.5:1).
bool isAccessibleBody(Color foreground, Color background) =>
    contrastRatio(foreground, background) >= 4.5;

/// AA gate for large text (≥ 3.0:1) — applies to ≥ 18.5pt bold or ≥ 24pt copy.
bool isAccessibleLarge(Color foreground, Color background) =>
    contrastRatio(foreground, background) >= 3.0;

/// Returns whichever of [light] or [dark] yields the higher contrast against
/// [background]. Used as the runtime fallback when a custom-color combination
/// would otherwise fail body-text contrast — the user never sees the
/// unreadable state.
///
/// Defaults reference [ColorPrimitives.inkOnDarkSurface] and
/// [ColorPrimitives.inkOnLightSurface] so the result still looks
/// intentional rather than clinical.
Color clampForReadability(
  Color background, {
  Color light = ColorPrimitives.inkOnDarkSurface,
  Color dark = ColorPrimitives.inkOnLightSurface,
}) {
  return contrastRatio(light, background) >= contrastRatio(dark, background) ? light : dark;
}
