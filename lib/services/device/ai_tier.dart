/// Device-capability tier (Spec 17). Drives whether AI affordances render
/// at all (Specs 18, 21) and which model variants are eligible.
///
/// Persisted as the lower-cased enum name in `settings_v2`
/// (`SettingsRepository.aiTier`); see [aiTierFromName] / [aiTierAsName] for
/// the round-trip.
enum AiTier {
  /// RAM ≥ 6 GB, modern OS (iOS 16+ / Android 13+), arm64. Runs Gemma 2-2B
  /// or comparable comfortably; Whisper-base or larger.
  full,

  /// RAM 4–6 GB (or unknown but otherwise modern; see classifier). Runs
  /// quantized Phi-3-mini-4k or Qwen2.5-1.5B; Whisper-tiny.
  compact,

  /// Below threshold, unsupported OS, or non-arm64. AI hidden.
  unsupported;

  /// Whether the device is eligible to load and run the on-device LLM
  /// (Spec 18). Both [full] and [compact] are eligible — model selection
  /// happens downstream of the tier.
  bool get canRunLlm => this != unsupported;

  /// Whether the device is eligible to run on-device Whisper transcription
  /// (Spec 21). Same gating as [canRunLlm].
  bool get canRunWhisper => this != unsupported;
}

/// Maps an [AiTier] to its persisted string form.
String aiTierAsName(AiTier tier) => tier.name;

/// Parses the persisted string form back to an [AiTier]. Returns
/// [AiTier.unsupported] for unrecognised input — conservative posture
/// matching the cold-start probe's "any failure resolves to unsupported".
AiTier aiTierFromName(String? name) {
  for (final tier in AiTier.values) {
    if (tier.name == name) return tier;
  }
  return AiTier.unsupported;
}
