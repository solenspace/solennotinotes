import 'package:flutter/material.dart';

import 'primitives.dart';

/// Spacing scale consumed via `context.tokens.spacing.<step>`. Spacing is
/// constant across overlays today (no per-note overlay alters it), but
/// exposed as a `ThemeExtension` so the access pattern stays uniform with
/// the rest of the token system.
@immutable
class NotiSpacing extends ThemeExtension<NotiSpacing> {
  const NotiSpacing({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
    required this.xxxl,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double xxxl;

  static const NotiSpacing standardSet = NotiSpacing(
    xs: SpacingPrimitives.xs,
    sm: SpacingPrimitives.sm,
    md: SpacingPrimitives.md,
    lg: SpacingPrimitives.lg,
    xl: SpacingPrimitives.xl,
    xxl: SpacingPrimitives.xxl,
    xxxl: SpacingPrimitives.xxxl,
  );

  @override
  NotiSpacing copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
    double? xxxl,
  }) {
    return NotiSpacing(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
      xxxl: xxxl ?? this.xxxl,
    );
  }

  @override
  NotiSpacing lerp(ThemeExtension<NotiSpacing>? other, double t) {
    if (other is! NotiSpacing) return this;
    return NotiSpacing(
      xs: _lerp(xs, other.xs, t),
      sm: _lerp(sm, other.sm, t),
      md: _lerp(md, other.md, t),
      lg: _lerp(lg, other.lg, t),
      xl: _lerp(xl, other.xl, t),
      xxl: _lerp(xxl, other.xxl, t),
      xxxl: _lerp(xxxl, other.xxxl, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
