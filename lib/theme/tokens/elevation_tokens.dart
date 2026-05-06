import 'package:flutter/material.dart';

import 'color_tokens.dart';

/// Five elevation steps mapped to surface tints (M3-style — we lighten
/// the surface instead of stacking shadows). Stored as `Color` so consumers
/// can paint backgrounds directly: `Container(color: tokens.elevation.e2)`.
@immutable
class NotiElevation extends ThemeExtension<NotiElevation> {
  const NotiElevation({
    required this.e0,
    required this.e1,
    required this.e2,
    required this.e3,
    required this.e4,
  });

  /// Base — no tint.
  final Color e0;

  /// +4% lightness — cards.
  final Color e1;

  /// +8% lightness — lifted cards on hover.
  final Color e2;

  /// +12% lightness — sheets, modals.
  final Color e3;

  /// +16% lightness — dialogs.
  final Color e4;

  static final NotiElevation bone = NotiElevation(
    e0: NotiColors.bone.surface,
    e1: _shift(NotiColors.bone.surface, 0.04),
    e2: _shift(NotiColors.bone.surface, 0.08),
    e3: _shift(NotiColors.bone.surface, 0.12),
    e4: _shift(NotiColors.bone.surface, 0.16),
  );

  static final NotiElevation dark = NotiElevation(
    e0: NotiColors.dark.surface,
    e1: _shift(NotiColors.dark.surface, 0.04),
    e2: _shift(NotiColors.dark.surface, 0.08),
    e3: _shift(NotiColors.dark.surface, 0.12),
    e4: _shift(NotiColors.dark.surface, 0.16),
  );

  /// Adjusts lightness in HSL space. Positive amount lightens, clamped to
  /// [0, 1]. Used for both bone and dark modes — bone moves toward white,
  /// dark moves toward white as well (overlay surfaces brighten on top of
  /// dark backgrounds in the M3 tint model).
  static Color _shift(Color base, double amount) {
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  @override
  NotiElevation copyWith({Color? e0, Color? e1, Color? e2, Color? e3, Color? e4}) {
    return NotiElevation(
      e0: e0 ?? this.e0,
      e1: e1 ?? this.e1,
      e2: e2 ?? this.e2,
      e3: e3 ?? this.e3,
      e4: e4 ?? this.e4,
    );
  }

  @override
  NotiElevation lerp(ThemeExtension<NotiElevation>? other, double t) {
    if (other is! NotiElevation) return this;
    return NotiElevation(
      e0: Color.lerp(e0, other.e0, t)!,
      e1: Color.lerp(e1, other.e1, t)!,
      e2: Color.lerp(e2, other.e2, t)!,
      e3: Color.lerp(e3, other.e3, t)!,
      e4: Color.lerp(e4, other.e4, t)!,
    );
  }
}
