import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/theme/contrast.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';

void main() {
  group('contrastRatio', () {
    test('black on white is 21:1 (max)', () {
      expect(
        contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21.0, 0.01),
      );
    });

    test('white on black is 21:1 (symmetry)', () {
      expect(
        contrastRatio(const Color(0xFFFFFFFF), const Color(0xFF000000)),
        closeTo(21.0, 0.01),
      );
    });

    test('identical colors return 1.0 (no contrast)', () {
      expect(
        contrastRatio(const Color(0xFF7F7F7F), const Color(0xFF7F7F7F)),
        closeTo(1.0, 0.01),
      );
    });

    test('mid-grey #777 on white sits just below the 4.5:1 AA gate', () {
      // WebAIM reference value: ≈ 4.48:1.
      final ratio = contrastRatio(const Color(0xFF777777), const Color(0xFFFFFFFF));
      expect(ratio, lessThan(4.5));
      expect(ratio, greaterThan(4.4));
    });
  });

  group('isAccessibleBody', () {
    test('passes at exactly 4.5:1 (AA body floor)', () {
      // black on white = 21:1, well above gate.
      expect(isAccessibleBody(const Color(0xFF000000), const Color(0xFFFFFFFF)), isTrue);
    });

    test('fails below 4.5:1', () {
      expect(isAccessibleBody(const Color(0xFF777777), const Color(0xFFFFFFFF)), isFalse);
    });
  });

  group('isAccessibleLarge', () {
    test('passes at 3.0:1', () {
      expect(isAccessibleLarge(const Color(0xFF767676), const Color(0xFFFFFFFF)), isTrue);
    });

    test('fails clearly below 3.0:1', () {
      expect(isAccessibleLarge(const Color(0xFFAAAAAA), const Color(0xFFFFFFFF)), isFalse);
    });
  });

  group('clampForReadability', () {
    test('returns the dark default for a light background', () {
      final result = clampForReadability(const Color(0xFFFFFFFF));
      expect(result, ColorPrimitives.inkOnLightSurface);
    });

    test('returns the light default for a dark background', () {
      final result = clampForReadability(const Color(0xFF111111));
      expect(result, ColorPrimitives.inkOnDarkSurface);
    });

    test('returned color always reaches AA against the input', () {
      const surfaces = [
        Color(0xFFEDE6D6), // bone
        Color(0xFFF5EFE2), // cream
        Color(0xFFE8D8BD), // sand
        Color(0xFF2D2D2D), // charcoal
        Color(0xFF1F2A35), // slate
        Color(0xFF1F2620), // moss
        Color(0xFF2A1F26), // plum
        Color(0xFF0F0F0F), // onyx
      ];
      for (final s in surfaces) {
        expect(
          contrastRatio(clampForReadability(s), s),
          greaterThanOrEqualTo(4.5),
          reason: 'clampForReadability(${s.toARGB32().toRadixString(16)}) must clear AA',
        );
      }
    });

    test('honors custom light/dark stops when supplied', () {
      final result = clampForReadability(
        const Color(0xFFFFFFFF),
        light: const Color(0xFFEEEEEE),
        dark: const Color(0xFF222222),
      );
      expect(result, const Color(0xFF222222));
    });
  });
}
