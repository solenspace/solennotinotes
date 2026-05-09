import 'package:flutter/material.dart';

/// The signature layer Spec 11's per-note overlay swaps. Carries the user
/// or note's emoji/glyph accent and tagline. Default is empty (no glyph,
/// empty tagline).
@immutable
class NotiSignature extends ThemeExtension<NotiSignature> {
  const NotiSignature({
    required this.accent,
    required this.tagline,
  });

  /// Single grapheme (emoji, kanji, etc.) or null if no signature accent.
  final String? accent;

  /// Short user-authored line (≤ 60 chars by upstream validation). Empty
  /// string when unset.
  final String tagline;

  static const NotiSignature empty = NotiSignature(accent: null, tagline: '');

  @override
  NotiSignature copyWith({Object? accent = _sentinel, String? tagline}) {
    return NotiSignature(
      accent: accent == _sentinel ? this.accent : accent as String?,
      tagline: tagline ?? this.tagline,
    );
  }

  @override
  NotiSignature lerp(ThemeExtension<NotiSignature>? other, double t) {
    if (other is! NotiSignature) return this;
    return t < 0.5 ? this : other;
  }

  static const Object _sentinel = Object();
}
