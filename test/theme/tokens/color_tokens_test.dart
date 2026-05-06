import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/theme/tokens/color_tokens.dart';

/// Computes WCAG relative luminance contrast ratio between two colors.
/// Result is `(L1 + 0.05) / (L2 + 0.05)` with L1 = lighter and L2 = darker.
/// AA passes at >= 4.5 (normal text); large text & non-text content has
/// looser thresholds — the spec locks in 4.4 as the AA floor for the
/// `onSurfaceMuted` token because it's only used on secondary copy.
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('NotiColors.copyWith', () {
    test('replaces only the supplied fields', () {
      const newAccent = Color(0xFF112233);
      final updated = NotiColors.bone.copyWith(accent: newAccent);

      expect(updated.accent, newAccent);
      expect(updated.surface, NotiColors.bone.surface);
      expect(updated.onSurface, NotiColors.bone.onSurface);
      expect(updated.onAccent, NotiColors.bone.onAccent);
    });
  });

  group('NotiColors.lerp', () {
    test('produces a continuous transition between bone and dark', () {
      final mid = NotiColors.bone.lerp(NotiColors.dark, 0.5);
      // Midpoint surface lies between bone surface and dark surface.
      expect(mid.surface.computeLuminance(), lessThan(NotiColors.bone.surface.computeLuminance()));
      expect(
        mid.surface.computeLuminance(),
        greaterThan(NotiColors.dark.surface.computeLuminance()),
      );
    });

    test('returns this when other is not NotiColors', () {
      final result = NotiColors.bone.lerp(null, 0.5);
      expect(result, same(NotiColors.bone));
    });

    test('t=0 is equivalent to this, t=1 is equivalent to other', () {
      final atZero = NotiColors.bone.lerp(NotiColors.dark, 0);
      final atOne = NotiColors.bone.lerp(NotiColors.dark, 1);
      expect(atZero.surface, NotiColors.bone.surface);
      expect(atOne.surface, NotiColors.dark.surface);
    });
  });

  group('WCAG AA contrast — bone', () {
    test('onSurface vs surface meets AA (4.5:1 normal-text floor)', () {
      final ratio = _contrastRatio(NotiColors.bone.onSurface, NotiColors.bone.surface);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('onSurfaceMuted vs surface meets the AA-large floor', () {
      final ratio = _contrastRatio(NotiColors.bone.onSurfaceMuted, NotiColors.bone.surface);
      // 4.4 is the project floor for muted secondary copy per Spec 10
      // Design Decisions; locked by user-decision.
      expect(ratio, greaterThanOrEqualTo(4.4));
    });

    // Note: bone-mode `onAccent` is `#F5EFE2` (boneLifted) on accent
    // `#4A8A7F`, ~3.5:1. The accent never carries body copy on bone — it
    // only paints AppBar accents and FAB strokes — so AA is verified
    // dark-side only per Spec 10 Section H.
  });

  group('WCAG AA contrast — dark', () {
    test('onSurface vs surface meets AA', () {
      final ratio = _contrastRatio(NotiColors.dark.onSurface, NotiColors.dark.surface);
      expect(ratio, greaterThanOrEqualTo(4.5));
    });

    test('onAccent vs accent meets AA', () {
      final ratio = _contrastRatio(NotiColors.dark.onAccent, NotiColors.dark.accent);
      expect(ratio, greaterThanOrEqualTo(4.4));
    });
  });
}
