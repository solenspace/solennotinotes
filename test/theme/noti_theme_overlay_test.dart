import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/note_overlay.dart';
import 'package:noti_notes_app/theme/contrast.dart';
import 'package:noti_notes_app/theme/noti_pattern_key.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';
import 'package:noti_notes_app/theme/tokens/color_tokens.dart';
import 'package:noti_notes_app/theme/tokens/pattern_backdrop_tokens.dart';
import 'package:noti_notes_app/theme/tokens/signature_tokens.dart';

Note _legacyNote({
  Color background = const Color(0xFFEDE6D6),
  Color font = const Color(0xFF0F0F0F),
  String? pattern,
  bool hasGradient = false,
  LinearGradient? gradient,
}) {
  return Note(
    {},
    null,
    pattern,
    [],
    null,
    gradient,
    id: 'fixture',
    title: '',
    content: '',
    dateCreated: DateTime(2024, 1, 1),
    colorBackground: background,
    fontColor: font,
    hasGradient: hasGradient,
  );
}

const _overlay = NotiThemeOverlay(
  surface: Color(0xFF1F2A35),
  surfaceVariant: Color(0xFF2A3744),
  accent: Color(0xFF7BAFD4),
  onAccent: Color(0xFF0E1822),
);

void main() {
  group('NotiThemeOverlay.applyToColors', () {
    test('patches surface, surfaceVariant, accent, onAccent, and focus', () {
      final base = NotiColors.bone;
      final patched = _overlay.applyToColors(base);

      expect(patched.surface, _overlay.surface);
      expect(patched.surfaceVariant, _overlay.surfaceVariant);
      expect(patched.accent, _overlay.accent);
      expect(patched.onAccent, _overlay.onAccent);
      expect(patched.focus, _overlay.accent, reason: 'focus mirrors accent');
    });

    test('preserves state colors (success / warning / error / info)', () {
      final base = NotiColors.bone;
      final patched = _overlay.applyToColors(base);

      expect(patched.success, base.success);
      expect(patched.warning, base.warning);
      expect(patched.error, base.error);
      expect(patched.info, base.info);
    });

    test('preserves ink stops (inkOnLightSurface / inkOnDarkSurface)', () {
      final base = NotiColors.bone;
      final patched = _overlay.applyToColors(base);

      expect(patched.inkOnLightSurface, base.inkOnLightSurface);
      expect(patched.inkOnDarkSurface, base.inkOnDarkSurface);
    });

    test('derives onSurface via clampForReadability when overlay leaves it null', () {
      final base = NotiColors.bone;
      final patched = _overlay.applyToColors(base);
      // Dark surface → clamp picks light default.
      expect(patched.onSurface, clampForReadability(_overlay.surface));
    });

    test('honors an explicit onSurface override on the overlay', () {
      const customInk = Color(0xFFAABBCC);
      final overlay = _overlay.copyWith(onSurface: customInk);
      final patched = overlay.applyToColors(NotiColors.bone);
      expect(patched.onSurface, customInk);
    });
  });

  group('NotiThemeOverlay.applyToPatternBackdrop', () {
    test('zeros opacity and keys when overlay has no pattern', () {
      final base = NotiPatternBackdrop.none;
      final patched = _overlay.applyToPatternBackdrop(base);

      expect(patched.patternKey, isNull);
      expect(patched.bodyOpacity, 0.0);
      expect(patched.headerOpacity, 0.0);
      expect(patched.headerHeightFraction, 0.0);
    });

    test('writes spec-defined opacities when pattern is set', () {
      final overlay = _overlay.copyWith(patternKey: NotiPatternKey.polygons);
      final patched = overlay.applyToPatternBackdrop(NotiPatternBackdrop.none);

      expect(patched.patternKey, 'polygons');
      expect(patched.bodyOpacity, 0.08);
      expect(patched.headerOpacity, 0.35);
      expect(patched.headerHeightFraction, 0.30);
    });

    test('body opacity stays inside the [0, 0.18] readability clamp', () {
      final overlay = _overlay.copyWith(patternKey: NotiPatternKey.waves);
      final patched = overlay.applyToPatternBackdrop(NotiPatternBackdrop.none);
      expect(patched.bodyOpacity, lessThanOrEqualTo(NotiPatternBackdrop.kMaxBodyOpacity));
    });
  });

  group('NotiThemeOverlay.applyToSignature', () {
    test('falls back to base when overlay fields are empty', () {
      const base = NotiSignature(accent: '☀', tagline: 'identity tagline');
      final patched = const NotiThemeOverlay(
        surface: Color(0xFF000000),
        surfaceVariant: Color(0xFF111111),
        accent: Color(0xFFFFFFFF),
        onAccent: Color(0xFF000000),
      ).applyToSignature(base);

      expect(patched.accent, '☀');
      expect(patched.tagline, 'identity tagline');
    });

    test('overrides accent and tagline when overlay supplies them', () {
      const base = NotiSignature.empty;
      final overlay = _overlay.copyWith(
        signatureAccent: '★',
        signatureTagline: 'note-specific',
      );
      final patched = overlay.applyToSignature(base);

      expect(patched.accent, '★');
      expect(patched.tagline, 'note-specific');
    });
  });

  group('NotiThemeOverlay.copyWith', () {
    test('clearPattern nulls out patternKey', () {
      final overlay = _overlay.copyWith(patternKey: NotiPatternKey.noise);
      final cleared = overlay.copyWith(clearPattern: true);
      expect(cleared.patternKey, isNull);
    });

    test('clearAccentChar nulls out signatureAccent', () {
      final overlay = _overlay.copyWith(signatureAccent: '✦');
      final cleared = overlay.copyWith(clearAccentChar: true);
      expect(cleared.signatureAccent, isNull);
    });

    test('clearOrigin nulls out fromIdentityId', () {
      final overlay = _overlay.copyWith(fromIdentityId: 'alice-123');
      final cleared = overlay.copyWith(clearOrigin: true);
      expect(cleared.fromIdentityId, isNull);
    });

    test('clearOnSurface nulls out the explicit onSurface override', () {
      final overlay = _overlay.copyWith(onSurface: const Color(0xFF112233));
      final cleared = overlay.copyWith(clearOnSurface: true);
      expect(cleared.onSurface, isNull);
    });
  });

  group('Note.toOverlay round-trip', () {
    test('non-gradient legacy note maps surface/font into overlay slots', () {
      final note = _legacyNote(
        background: const Color(0xFFEDE6D6),
        font: const Color(0xFF111111),
      );
      final overlay = note.toOverlay();

      expect(overlay.surface, const Color(0xFFEDE6D6));
      expect(overlay.onSurface, const Color(0xFF111111));
      expect(
        overlay.onAccent,
        const Color(0xFFEDE6D6),
        reason: 'onAccent mirrors the surface for legacy notes',
      );
      expect(overlay.patternKey, isNull);
      expect(overlay.signatureAccent, isNull);
      expect(overlay.fromIdentityId, isNull);
    });

    test('gradient legacy note encodes gradient end color into accent', () {
      final note = _legacyNote(
        hasGradient: true,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFB6B6), Color(0xFF614385)],
        ),
      );
      final overlay = note.toOverlay();
      expect(overlay.accent, const Color(0xFF614385));
    });

    test('empty-colors gradient falls back to non-gradient accent derivation', () {
      // Defensive: malformed legacy note with hasGradient=true but no colors.
      final note = _legacyNote(
        hasGradient: true,
        gradient: const LinearGradient(colors: <Color>[]),
      );
      // Should not throw and should derive accent from font/background lerp.
      final overlay = note.toOverlay();
      expect(overlay.accent, isNotNull);
    });

    test('parses patternImage string into a NotiPatternKey', () {
      final note = _legacyNote(pattern: 'polygons');
      expect(note.toOverlay().patternKey, NotiPatternKey.polygons);
    });

    test('unknown patternImage string maps to null', () {
      final note = _legacyNote(pattern: 'not-a-real-key');
      expect(note.toOverlay().patternKey, isNull);
    });
  });

  group('NotiThemeOverlay equality', () {
    test('two overlays with identical fields compare equal', () {
      const a = NotiThemeOverlay(
        surface: Color(0xFF111111),
        surfaceVariant: Color(0xFF222222),
        accent: Color(0xFFAABBCC),
        onAccent: Color(0xFFFFFFFF),
        signatureAccent: '★',
      );
      const b = NotiThemeOverlay(
        surface: Color(0xFF111111),
        surfaceVariant: Color(0xFF222222),
        accent: Color(0xFFAABBCC),
        onAccent: Color(0xFFFFFFFF),
        signatureAccent: '★',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('overlays differing in fromIdentityId are not equal', () {
      final a = _overlay.copyWith(fromIdentityId: 'alice');
      final b = _overlay.copyWith(fromIdentityId: 'bob');
      expect(a == b, isFalse);
    });
  });
}
