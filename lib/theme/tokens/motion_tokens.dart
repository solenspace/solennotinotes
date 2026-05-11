import 'package:flutter/material.dart';

import 'primitives.dart';

/// Halves [base] when the OS reports a reduce-motion preference via
/// `MediaQuery.disableAnimationsOf(context)`. Returns [base] unchanged
/// otherwise. The token table itself stays canonical; this helper is the
/// single place call sites should reach for when consuming any
/// `DurationPrimitives.*` or `tokens.motion.*` duration so reduced-motion
/// behavior is consistent across the app (WCAG 2.3.3).
Duration motionFor(BuildContext context, Duration base) {
  return MediaQuery.disableAnimationsOf(context) ? base ~/ 2 : base;
}

/// Four motion tiers consumed app-wide. Reduced-motion handling lives at
/// the call site via [motionFor]: when `MediaQuery.disableAnimationsOf`
/// is true the duration is halved. The token itself stays canonical.
@immutable
class NotiMotion extends ThemeExtension<NotiMotion> {
  const NotiMotion({
    required this.fast,
    required this.standard,
    required this.calm,
    required this.pattern,
    required this.fastCurve,
    required this.standardCurve,
    required this.calmCurve,
    required this.patternCurve,
  });

  /// 120ms — chips, hover, focus.
  final Duration fast;

  /// 240ms — page transitions, sheets.
  final Duration standard;

  /// 480ms — note-card open, share success.
  final Duration calm;

  /// 720ms — overlay swap inside the editor.
  final Duration pattern;

  final Curve fastCurve;
  final Curve standardCurve;
  final Curve calmCurve;
  final Curve patternCurve;

  static const NotiMotion standardSet = NotiMotion(
    fast: DurationPrimitives.fast,
    standard: DurationPrimitives.standard,
    calm: DurationPrimitives.calm,
    pattern: DurationPrimitives.pattern,
    fastCurve: CurvePrimitives.fast,
    standardCurve: CurvePrimitives.standard,
    calmCurve: CurvePrimitives.calm,
    patternCurve: CurvePrimitives.pattern,
  );

  @override
  NotiMotion copyWith({
    Duration? fast,
    Duration? standard,
    Duration? calm,
    Duration? pattern,
    Curve? fastCurve,
    Curve? standardCurve,
    Curve? calmCurve,
    Curve? patternCurve,
  }) {
    return NotiMotion(
      fast: fast ?? this.fast,
      standard: standard ?? this.standard,
      calm: calm ?? this.calm,
      pattern: pattern ?? this.pattern,
      fastCurve: fastCurve ?? this.fastCurve,
      standardCurve: standardCurve ?? this.standardCurve,
      calmCurve: calmCurve ?? this.calmCurve,
      patternCurve: patternCurve ?? this.patternCurve,
    );
  }

  @override
  NotiMotion lerp(ThemeExtension<NotiMotion>? other, double t) {
    if (other is! NotiMotion) return this;
    // Durations and curves are discrete; pick at the midpoint.
    return t < 0.5 ? this : other;
  }
}
