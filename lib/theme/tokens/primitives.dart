import 'package:flutter/animation.dart';
import 'package:flutter/material.dart';

/// Raw token primitives. Public so sibling files in `lib/theme/tokens/` can
/// reference them as `ColorPrimitives.boneBase` etc., but treated as
/// library-private by convention: no file outside `lib/theme/tokens/` and
/// `lib/theme/curated_palettes.dart` should import these directly. The
/// `no_hardcoded_color` custom_lint rule enforces this for color literals.
class ColorPrimitives {
  ColorPrimitives._();

  static const Color boneBase = Color(0xFFEDE6D6);
  static const Color boneLifted = Color(0xFFF5EFE2);
  static const Color boneSunk = Color(0xFFE0D8C5);
  static const Color boneVariant = Color(0xFFE8D8BD);

  static const Color inkPrimary = Color(0xFF1C1B1A);
  static const Color inkSecondary = Color(0xFF4A4640);
  static const Color inkSubtle = Color(0xFF6B665D);
  static const Color inkBarely = Color(0xFF9B958A);

  static const Color accentDefault = Color(0xFF4A8A7F);
  static const Color accentMuted = Color(0xFF6B9C92);
  static const Color onAccent = Color(0xFFF5EFE2);

  static const Color accentSlate = Color(0xFF4A5F8F);
  static const Color accentRose = Color(0xFFA87878);
  static const Color accentOlive = Color(0xFF6B7A4A);
  static const Color accentCharcoal = Color(0xFF3A3A3A);

  static const Color grey900 = Color(0xFF1A1A1A);
  static const Color grey800 = Color(0xFF2D2D2D);
  static const Color grey750 = Color(0xFF383838);
  static const Color grey700 = Color(0xFF454545);
  static const Color grey300 = Color(0xFFC9C2B6);
  static const Color grey200 = Color(0xFFD9D9D9);
  static const Color grey050 = Color(0xFFF2EFEA);
  static const Color darkAccent = Color(0xFFE5B26B);

  static const Color success = Color(0xFF5C7A4A);
  static const Color warning = Color(0xFFA87B2D);
  static const Color error = Color(0xFFA0473A);
  static const Color info = Color(0xFF3F6B8A);

  /// Pre-known high-contrast inks for note backgrounds whose luminance is
  /// computed at runtime. These two pair against the per-note swatches
  /// defined in `curated_palettes.dart`, not the chrome `onSurface` token.
  static const Color inkOnLightSurface = inkPrimary;
  static const Color inkOnDarkSurface = grey050;
}

class RadiusPrimitives {
  RadiusPrimitives._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 22;
  static const double pill = 999;
}

class DurationPrimitives {
  DurationPrimitives._();

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 240);
  static const Duration calm = Duration(milliseconds: 480);
  static const Duration pattern = Duration(milliseconds: 720);
}

class CurvePrimitives {
  CurvePrimitives._();

  static const Curve fast = Curves.easeOut;
  static const Curve standard = Curves.easeInOut;
  static const Curve calm = Curves.easeOutCubic;
  static const Curve pattern = Cubic(0.65, 0, 0.35, 1);
}

class TextSizePrimitives {
  TextSizePrimitives._();

  static const double display = 32;
  static const double headlineLg = 24;
  static const double headlineMd = 20;
  static const double titleLg = 18;
  static const double titleMd = 17;
  static const double titleSm = 15;
  static const double bodyLg = 17;
  static const double bodyMd = 14;
  static const double bodySm = 13;
  static const double labelLg = 14;
  static const double labelMd = 13;
  static const double labelSm = 11;
}

class SpacingPrimitives {
  SpacingPrimitives._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}
