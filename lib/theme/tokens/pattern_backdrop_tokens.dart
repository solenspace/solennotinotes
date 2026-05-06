import 'package:flutter/material.dart';

/// The pattern backdrop layer Spec 11's per-note overlay swaps for each
/// open note. The base theme registers `NotiPatternBackdrop.none`; an
/// overlay clones the active extension and patches it via [copyWith].
///
/// `bodyOpacity` is bounded to 0.08–0.18 by design (subtle texture); the
/// constructor clamps. `headerOpacity` is 1.0 inside the header band, 0
/// below. `headerHeightFraction` controls the band height as a fraction of
/// the editor surface (0.25–0.35 by design).
@immutable
class NotiPatternBackdrop extends ThemeExtension<NotiPatternBackdrop> {
  NotiPatternBackdrop({
    required this.patternKey,
    required double bodyOpacity,
    required double headerOpacity,
    required double headerHeightFraction,
  })  : bodyOpacity = bodyOpacity.clamp(0.0, kMaxBodyOpacity),
        headerOpacity = headerOpacity.clamp(0.0, 1.0),
        headerHeightFraction = headerHeightFraction.clamp(0.0, 1.0);

  /// Hard ceiling on body-text pattern opacity. Spec 11 §3.2 readability
  /// guardrail: above 18% the pattern starts interfering with body copy
  /// even on AA-validated palettes. The header band may go full opacity
  /// because no body text sits inside it.
  static const double kMaxBodyOpacity = 0.18;

  /// Persisted key on `NotiIdentity.signaturePatternKey` / per-note
  /// equivalent. Null = no pattern.
  final String? patternKey;

  /// Opacity of the pattern below the header band. 0 disables the body
  /// pattern entirely; 0.08–0.18 is the design-recommended range.
  final double bodyOpacity;

  /// Opacity of the pattern inside the header band. Typically 1.0 when a
  /// pattern is set.
  final double headerOpacity;

  /// Fraction of the editor surface occupied by the header band.
  /// Design-recommended range: 0.25–0.35.
  final double headerHeightFraction;

  static final NotiPatternBackdrop none = NotiPatternBackdrop(
    patternKey: null,
    bodyOpacity: 0,
    headerOpacity: 0,
    headerHeightFraction: 0,
  );

  @override
  NotiPatternBackdrop copyWith({
    Object? patternKey = _sentinel,
    double? bodyOpacity,
    double? headerOpacity,
    double? headerHeightFraction,
  }) {
    return NotiPatternBackdrop(
      patternKey: patternKey == _sentinel ? this.patternKey : patternKey as String?,
      bodyOpacity: bodyOpacity ?? this.bodyOpacity,
      headerOpacity: headerOpacity ?? this.headerOpacity,
      headerHeightFraction: headerHeightFraction ?? this.headerHeightFraction,
    );
  }

  @override
  NotiPatternBackdrop lerp(ThemeExtension<NotiPatternBackdrop>? other, double t) {
    if (other is! NotiPatternBackdrop) return this;
    return NotiPatternBackdrop(
      patternKey: t < 0.5 ? patternKey : other.patternKey,
      bodyOpacity: bodyOpacity + (other.bodyOpacity - bodyOpacity) * t,
      headerOpacity: headerOpacity + (other.headerOpacity - headerOpacity) * t,
      headerHeightFraction:
          headerHeightFraction + (other.headerHeightFraction - headerHeightFraction) * t,
    );
  }

  static const Object _sentinel = Object();
}
