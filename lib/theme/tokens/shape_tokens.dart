import 'package:flutter/material.dart';

import 'primitives.dart';

/// Five named radii from the locked design vocabulary
/// (`pill: 999, lg: 22, md: 14, sm: 8, xs: 4`). Both raw doubles and
/// pre-built `BorderRadius` objects are exposed so consumers can pass
/// either form without rebuilding it on every frame.
@immutable
class NotiShape extends ThemeExtension<NotiShape> {
  const NotiShape({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.pill,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double pill;

  BorderRadius get xsRadius => BorderRadius.circular(xs);
  BorderRadius get smRadius => BorderRadius.circular(sm);
  BorderRadius get mdRadius => BorderRadius.circular(md);
  BorderRadius get lgRadius => BorderRadius.circular(lg);
  BorderRadius get pillRadius => BorderRadius.circular(pill);

  static const NotiShape standardSet = NotiShape(
    xs: RadiusPrimitives.xs,
    sm: RadiusPrimitives.sm,
    md: RadiusPrimitives.md,
    lg: RadiusPrimitives.lg,
    pill: RadiusPrimitives.pill,
  );

  @override
  NotiShape copyWith({double? xs, double? sm, double? md, double? lg, double? pill}) {
    return NotiShape(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      pill: pill ?? this.pill,
    );
  }

  @override
  NotiShape lerp(ThemeExtension<NotiShape>? other, double t) {
    if (other is! NotiShape) return this;
    return NotiShape(
      xs: lerpDouble(xs, other.xs, t),
      sm: lerpDouble(sm, other.sm, t),
      md: lerpDouble(md, other.md, t),
      lg: lerpDouble(lg, other.lg, t),
      pill: lerpDouble(pill, other.pill, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
