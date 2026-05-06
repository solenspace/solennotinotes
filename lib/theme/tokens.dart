import 'package:flutter/material.dart';

import 'tokens/color_tokens.dart';
import 'tokens/elevation_tokens.dart';
import 'tokens/motion_tokens.dart';
import 'tokens/pattern_backdrop_tokens.dart';
import 'tokens/shape_tokens.dart';
import 'tokens/signature_tokens.dart';
import 'tokens/spacing_tokens.dart';
import 'tokens/typography_tokens.dart';

export 'tokens/color_tokens.dart';
export 'tokens/elevation_tokens.dart';
export 'tokens/motion_tokens.dart';
export 'tokens/pattern_backdrop_tokens.dart';
export 'tokens/primitives.dart';
export 'tokens/shape_tokens.dart';
export 'tokens/signature_tokens.dart';
export 'tokens/spacing_tokens.dart';
export 'tokens/typography_tokens.dart';

/// Aggregator returned by `context.tokens` so call sites read tokens with a
/// single short hop: `context.tokens.colors.surface`,
/// `context.tokens.spacing.md`. The eight `ThemeExtension`s are wired into
/// `ThemeData` by `AppTheme._build` — if any is missing here we throw,
/// because that's a setup bug rather than a runtime condition.
class Tokens {
  const Tokens({
    required this.colors,
    required this.text,
    required this.motion,
    required this.shape,
    required this.elevation,
    required this.spacing,
    required this.patternBackdrop,
    required this.signature,
  });

  final NotiColors colors;
  final NotiText text;
  final NotiMotion motion;
  final NotiShape shape;
  final NotiElevation elevation;
  final NotiSpacing spacing;
  final NotiPatternBackdrop patternBackdrop;
  final NotiSignature signature;
}

extension BuildContextTokens on BuildContext {
  Tokens get tokens {
    final theme = Theme.of(this);
    final colors = theme.extension<NotiColors>();
    final text = theme.extension<NotiText>();
    final motion = theme.extension<NotiMotion>();
    final shape = theme.extension<NotiShape>();
    final elevation = theme.extension<NotiElevation>();
    final spacing = theme.extension<NotiSpacing>();
    final patternBackdrop = theme.extension<NotiPatternBackdrop>();
    final signature = theme.extension<NotiSignature>();
    if (colors == null ||
        text == null ||
        motion == null ||
        shape == null ||
        elevation == null ||
        spacing == null ||
        patternBackdrop == null ||
        signature == null) {
      throw StateError(
        'Theme is missing required NotiNotes ThemeExtensions. '
        'AppTheme.bone()/AppTheme.dark() must register all eight.',
      );
    }
    return Tokens(
      colors: colors,
      text: text,
      motion: motion,
      shape: shape,
      elevation: elevation,
      spacing: spacing,
      patternBackdrop: patternBackdrop,
      signature: signature,
    );
  }
}
