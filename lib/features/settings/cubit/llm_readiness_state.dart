import 'package:equatable/equatable.dart';

/// Phase of the LLM-model download flow as observed by the UI. Mirrors the
/// internal phases of `LlmModelDownloader.download()` but is decoupled —
/// the UI talks to this enum, not to the downloader's `DownloadProgress`
/// sealed class, so a future change to the downloader's reporting (e.g.
/// adding "checksumming" mid-stream) does not ripple into widget code.
enum LlmReadinessPhase {
  /// No model on disk and the user has not opted in. Settings row reads
  /// "Enable AI assist (~640 MB)".
  idle,

  /// Bytes are streaming to the partial sidecar. `progressBytes` /
  /// `totalBytes` drive the progress bar.
  downloading,

  /// Download finished; SHA-256 verification in progress. Always brief
  /// (single-pass digest already accumulated during download), but exposed
  /// as a distinct phase so VoiceOver can announce the transition.
  verifying,

  /// The canonical file is on disk and verified. Settings row reads "AI
  /// assist enabled".
  ready,

  /// Network error / hash mismatch / disk full. `failureReason` carries
  /// the user-visible message; the row offers a retry affordance.
  failed,
}

/// State for [LlmReadinessCubit]. The phase + the two bytes counts +
/// `failureReason` are the entire UI surface — anything richer (per-byte
/// throughput, ETAs) belongs to the cubit's internals, not the state.
class LlmReadinessState extends Equatable {
  const LlmReadinessState({
    required this.phase,
    this.progressBytes = 0,
    this.totalBytes = 0,
    this.failureReason,
  });

  /// Initial state — no model, no opt-in. Cubit constructor seeds this.
  const LlmReadinessState.idle()
      : phase = LlmReadinessPhase.idle,
        progressBytes = 0,
        totalBytes = 0,
        failureReason = null;

  final LlmReadinessPhase phase;
  final int progressBytes;
  final int totalBytes;
  final String? failureReason;

  /// 0.0–1.0 progress fraction, clamped. Exposed here so widgets do not
  /// re-derive it (and inadvertently divide by zero before the first
  /// `Content-Length` arrives).
  double get progressFraction {
    if (totalBytes <= 0) return 0;
    final raw = progressBytes / totalBytes;
    if (raw <= 0) return 0;
    if (raw >= 1) return 1;
    return raw;
  }

  LlmReadinessState copyWith({
    LlmReadinessPhase? phase,
    int? progressBytes,
    int? totalBytes,
    String? failureReason,
    bool clearFailureReason = false,
  }) {
    return LlmReadinessState(
      phase: phase ?? this.phase,
      progressBytes: progressBytes ?? this.progressBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      failureReason: clearFailureReason ? null : (failureReason ?? this.failureReason),
    );
  }

  @override
  List<Object?> get props => [phase, progressBytes, totalBytes, failureReason];
}
