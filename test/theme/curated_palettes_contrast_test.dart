import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/theme/contrast.dart';
import 'package:noti_notes_app/theme/curated_palettes.dart';

/// Build-time gate over every entry in [kCuratedPalettes]. If anyone adds
/// or retunes a swatch and the resulting pair fails WCAG AA at 4.5:1, the
/// build fails until the palette is corrected.
void main() {
  test('kCuratedPalettes and kCuratedPaletteNames stay parallel', () {
    expect(
      kCuratedPalettes.length,
      kCuratedPaletteNames.length,
      reason: 'Each palette must have a parallel-indexed name for a11y labels.',
    );
    expect(kCuratedPalettes.length, 12, reason: 'Spec 11 ships exactly 12 starter palettes.');
  });

  for (var i = 0; i < kCuratedPalettes.length; i++) {
    final palette = kCuratedPalettes[i];
    final name = kCuratedPaletteNames[i];

    group('curated palette: $name', () {
      test('accent vs onAccent meets AA body-text contrast (4.5:1)', () {
        final ratio = contrastRatio(palette.accent, palette.onAccent);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$name accent/onAccent ratio is $ratio — below AA body floor.',
        );
      });

      test('clampForReadability(surface) vs surface meets AA body contrast', () {
        final fg = clampForReadability(palette.surface);
        final ratio = contrastRatio(fg, palette.surface);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$name body text against surface falls below AA at $ratio.',
        );
      });
    });
  }
}
