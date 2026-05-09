import '../device/ai_tier.dart';
import 'model_download_spec.dart';

/// Frozen identity of the on-device Whisper model files shipped with v1
/// of the transcription flow (Spec 21). Two variants ride the same
/// download surface as the LLM (`ModelDownloader`); the `AiTier`
/// classifier picks at runtime per architecture decision #7:
///
///   * `AiTier.full`    → [baseEn]   (~140 MB, ~6× realtime)
///   * `AiTier.compact` → [tinyEn]   (~75 MB, ~10× realtime)
///   * `AiTier.unsupported` — Whisper affordances do not render at all
///     (Spec 21 § Success Criteria).
///
/// These are deliberately top-level constants, not configuration. The
/// whole point of the offline invariant (architecture.md #1) is that
/// the user can audit every outbound URL the app will hit; making the
/// URLs swappable at runtime would defeat the audit.
///
/// **TODO before merge** — the [ModelDownloadSpec.sha256] and
/// [ModelDownloadSpec.totalBytes] values below are placeholders. The
/// implementer (or flutter-expert during the validation pass) must pull
/// the canonical values from the LFS pointer files at
/// `https://huggingface.co/ggerganov/whisper.cpp/raw/main/ggml-{tiny,base}.en.bin`
/// and replace them. The downloader's hash check fails closed on a
/// mismatch (the partial file is deleted; the user sees a `failed`
/// state) — so a placeholder hash is safe in development but must be
/// real before any user installs an APK / IPA. Track in
/// `context/progress-tracker.md` open questions if not resolved at
/// merge.
class WhisperModelConstants {
  /// Schema version of the Whisper constants. Bumped when any variant's
  /// `filename` / `url` / `sha256` change in lock-step.
  static const String version = '0.1.0';

  /// Whisper-tiny English-only (`ggml-tiny.en.bin`). Selected for
  /// `AiTier.compact`.
  ///
  /// Source-of-truth mirror: `ggerganov/whisper.cpp` on Hugging Face,
  /// the canonical distribution channel for whisper.cpp `.bin` weights.
  /// Same provenance posture as the LLM model (`TheBloke/...` mirror).
  static const ModelDownloadSpec tinyEn = ModelDownloadSpec(
    subdirectory: 'whisper',
    filename: 'ggml-tiny.en.bin',
    url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin',
    // TODO(spec-21-merge): replace with the real hex SHA-256 from the
    // LFS pointer file at `.../raw/main/ggml-tiny.en.bin`. Placeholder
    // fails the on-disk hash check by design.
    sha256: 'pending-flutter-expert-validation-tinyEn',
    // TODO(spec-21-merge): replace with the real byte size; ~75 MB is
    // the published figure from whisper.cpp README.
    totalBytes: 77700000,
    version: version,
  );

  /// Whisper-base English-only (`ggml-base.en.bin`). Selected for
  /// `AiTier.full`.
  static const ModelDownloadSpec baseEn = ModelDownloadSpec(
    subdirectory: 'whisper',
    filename: 'ggml-base.en.bin',
    url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin',
    // TODO(spec-21-merge): replace with the real hex SHA-256 from the
    // LFS pointer file at `.../raw/main/ggml-base.en.bin`.
    sha256: 'pending-flutter-expert-validation-baseEn',
    // TODO(spec-21-merge): replace with the real byte size; ~142 MB is
    // the published figure from whisper.cpp README.
    totalBytes: 147950000,
    version: version,
  );

  /// Resolves the variant for [tier] per architecture decision #7.
  /// Throws [StateError] for [AiTier.unsupported]; UI must gate the
  /// affordance with `aiTier.canRunWhisper` before calling.
  static ModelDownloadSpec specForTier(AiTier tier) {
    switch (tier) {
      case AiTier.full:
        return baseEn;
      case AiTier.compact:
        return tinyEn;
      case AiTier.unsupported:
        throw StateError(
          'WhisperModelConstants.specForTier(unsupported): callers must '
          'check `aiTier.canRunWhisper` before resolving a Whisper spec.',
        );
    }
  }

  const WhisperModelConstants._();
}
