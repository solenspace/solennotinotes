import 'package:flutter/material.dart';

import 'primitives.dart';

/// Semantic color roles consumed across the app via
/// `context.tokens.colors.<role>`. Spec 11's per-note overlay clones the
/// active instance and patches it via [copyWith]; [lerp] gives free
/// animated transitions between the base theme and a note's overlay.
@immutable
class NotiColors extends ThemeExtension<NotiColors> {
  const NotiColors({
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceMuted,
    required this.surfaceElevated,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.onSurfaceSubtle,
    required this.accent,
    required this.accentMuted,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.divider,
    required this.focus,
    required this.inkOnLightSurface,
    required this.inkOnDarkSurface,
  });

  final Color surface;
  final Color surfaceVariant;
  final Color surfaceMuted;
  final Color surfaceElevated;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color onSurfaceSubtle;
  final Color accent;
  final Color accentMuted;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color divider;
  final Color focus;
  final Color inkOnLightSurface;
  final Color inkOnDarkSurface;

  static const NotiColors bone = NotiColors(
    surface: ColorPrimitives.boneBase,
    surfaceVariant: ColorPrimitives.boneLifted,
    surfaceMuted: ColorPrimitives.boneSunk,
    surfaceElevated: ColorPrimitives.boneLifted,
    onSurface: ColorPrimitives.inkPrimary,
    onSurfaceMuted: ColorPrimitives.inkSecondary,
    onSurfaceSubtle: ColorPrimitives.inkSubtle,
    accent: ColorPrimitives.accentDefault,
    accentMuted: ColorPrimitives.accentMuted,
    onAccent: ColorPrimitives.onAccent,
    success: ColorPrimitives.success,
    warning: ColorPrimitives.warning,
    error: ColorPrimitives.error,
    info: ColorPrimitives.info,
    divider: ColorPrimitives.boneSunk,
    focus: ColorPrimitives.accentDefault,
    inkOnLightSurface: ColorPrimitives.inkOnLightSurface,
    inkOnDarkSurface: ColorPrimitives.inkOnDarkSurface,
  );

  static const NotiColors dark = NotiColors(
    surface: ColorPrimitives.grey800,
    surfaceVariant: ColorPrimitives.grey750,
    surfaceMuted: ColorPrimitives.grey900,
    surfaceElevated: ColorPrimitives.grey700,
    onSurface: ColorPrimitives.grey050,
    onSurfaceMuted: ColorPrimitives.grey300,
    onSurfaceSubtle: ColorPrimitives.inkBarely,
    accent: ColorPrimitives.darkAccent,
    accentMuted: ColorPrimitives.accentMuted,
    onAccent: ColorPrimitives.grey900,
    success: ColorPrimitives.success,
    warning: ColorPrimitives.warning,
    error: ColorPrimitives.error,
    info: ColorPrimitives.info,
    divider: ColorPrimitives.grey700,
    focus: ColorPrimitives.darkAccent,
    inkOnLightSurface: ColorPrimitives.inkOnLightSurface,
    inkOnDarkSurface: ColorPrimitives.inkOnDarkSurface,
  );

  @override
  NotiColors copyWith({
    Color? surface,
    Color? surfaceVariant,
    Color? surfaceMuted,
    Color? surfaceElevated,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? onSurfaceSubtle,
    Color? accent,
    Color? accentMuted,
    Color? onAccent,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? divider,
    Color? focus,
    Color? inkOnLightSurface,
    Color? inkOnDarkSurface,
  }) {
    return NotiColors(
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      onSurfaceSubtle: onSurfaceSubtle ?? this.onSurfaceSubtle,
      accent: accent ?? this.accent,
      accentMuted: accentMuted ?? this.accentMuted,
      onAccent: onAccent ?? this.onAccent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      divider: divider ?? this.divider,
      focus: focus ?? this.focus,
      inkOnLightSurface: inkOnLightSurface ?? this.inkOnLightSurface,
      inkOnDarkSurface: inkOnDarkSurface ?? this.inkOnDarkSurface,
    );
  }

  @override
  NotiColors lerp(ThemeExtension<NotiColors>? other, double t) {
    if (other is! NotiColors) return this;
    return NotiColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      onSurfaceSubtle: Color.lerp(onSurfaceSubtle, other.onSurfaceSubtle, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      inkOnLightSurface: Color.lerp(inkOnLightSurface, other.inkOnLightSurface, t)!,
      inkOnDarkSurface: Color.lerp(inkOnDarkSurface, other.inkOnDarkSurface, t)!,
    );
  }
}
