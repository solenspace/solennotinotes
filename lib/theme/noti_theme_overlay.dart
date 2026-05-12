import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

import 'contrast.dart';
import 'noti_pattern_key.dart';
import 'tokens/color_tokens.dart';
import 'tokens/pattern_backdrop_tokens.dart';
import 'tokens/signature_tokens.dart';

/// A note's per-note visual overlay. Selectively replaces the base theme's
/// surface + accent + pattern + signature when the note is rendered, while
/// leaving state colors (success/warning/error/info), divider, and ink
/// stops untouched.
///
/// Equality is deep so `BlocBuilder.buildWhen` can compare overlays cheaply.
class NotiThemeOverlay extends Equatable {
  const NotiThemeOverlay({
    required this.surface,
    required this.surfaceVariant,
    required this.accent,
    required this.onAccent,
    this.onSurface,
    this.patternKey,
    this.signatureAccent,
    this.signatureTagline = '',
    this.fromIdentityId,
  });

  final Color surface;
  final Color surfaceVariant;
  final Color accent;
  final Color onAccent;

  /// Foreground for body text. If null, [applyToColors] derives a safe value
  /// via [clampForReadability].
  final Color? onSurface;

  final NotiPatternKey? patternKey;

  /// Single user-perceived character (emoji or glyph) shown as the note's
  /// signature mark on the home grid and editor chrome.
  final String? signatureAccent;

  /// Short user-authored line (≤ 60 chars by upstream validation).
  final String signatureTagline;

  /// Identity id of the note's authoring user. Null on locally-authored
  /// notes; non-null on notes received via share. Drives the
  /// "from @sender" chip in the editor AppBar.
  final String? fromIdentityId;

  /// Returns a copy with the supplied fields replaced. Use the `clear*`
  /// flags to null out a field — `null` parameters mean "keep current"
  /// because Dart's optional-named-args can't disambiguate "absent" from
  /// "null".
  NotiThemeOverlay copyWith({
    Color? surface,
    Color? surfaceVariant,
    Color? accent,
    Color? onAccent,
    Color? onSurface,
    NotiPatternKey? patternKey,
    String? signatureAccent,
    String? signatureTagline,
    String? fromIdentityId,
    bool clearOnSurface = false,
    bool clearPattern = false,
    bool clearAccentChar = false,
    bool clearOrigin = false,
  }) {
    return NotiThemeOverlay(
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      onSurface: clearOnSurface ? null : (onSurface ?? this.onSurface),
      patternKey: clearPattern ? null : (patternKey ?? this.patternKey),
      signatureAccent: clearAccentChar ? null : (signatureAccent ?? this.signatureAccent),
      signatureTagline: signatureTagline ?? this.signatureTagline,
      fromIdentityId: clearOrigin ? null : (fromIdentityId ?? this.fromIdentityId),
    );
  }

  /// Patches the surface + accent + focus slots of [base] with this overlay.
  /// State colors, dividers, and ink stops are preserved so receivers of a
  /// shared note still see project-consistent error/warning/info colors.
  ///
  /// `surfaceElevated` and `surfaceMuted` are interpolated toward the base
  /// theme's stops so the overlay's elevation hierarchy reads intentional
  /// rather than flat — `lerp(surface, base.surfaceElevated, 0.4)` gives a
  /// noticeable but subtle lift.
  NotiColors applyToColors(NotiColors base) {
    final resolvedOnSurface = onSurface ?? clampForReadability(surface);
    final safeOnSurface = isAccessibleBody(resolvedOnSurface, surface)
        ? resolvedOnSurface
        : clampForReadability(surface);
    final safeOnAccent =
        isAccessibleBody(onAccent, accent) ? onAccent : clampForReadability(accent);
    return base.copyWith(
      surface: surface,
      surfaceVariant: surfaceVariant,
      surfaceElevated: Color.lerp(surface, base.surfaceElevated, 0.4)!,
      surfaceMuted: Color.lerp(surface, base.surfaceMuted, 0.6)!,
      onSurface: safeOnSurface,
      accent: accent,
      onAccent: safeOnAccent,
      focus: accent,
    );
  }

  /// Patches the pattern backdrop. When [patternKey] is null the pattern
  /// layer is fully disabled (zero opacities, zero header band).
  NotiPatternBackdrop applyToPatternBackdrop(NotiPatternBackdrop base) {
    if (patternKey == null) {
      return base.copyWith(
        patternKey: null,
        bodyOpacity: 0,
        headerOpacity: 0,
        headerHeightFraction: 0,
      );
    }
    return base.copyWith(
      patternKey: patternKey!.name,
      bodyOpacity: 0.12,
      headerOpacity: 1.0,
      headerHeightFraction: 0.30,
    );
  }

  /// Patches the signature layer. Empty overlay fields fall back to [base]
  /// so the user's identity tagline can show through when a note doesn't
  /// override it.
  NotiSignature applyToSignature(NotiSignature base) {
    return base.copyWith(
      accent: signatureAccent ?? base.accent,
      tagline: signatureTagline.isEmpty ? base.tagline : signatureTagline,
    );
  }

  @override
  List<Object?> get props => [
        surface,
        surfaceVariant,
        accent,
        onAccent,
        onSurface,
        patternKey,
        signatureAccent,
        signatureTagline,
        fromIdentityId,
      ];
}
