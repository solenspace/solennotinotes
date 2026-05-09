import 'package:equatable/equatable.dart';

/// Phase of the Whisper-model download flow as observed by the UI.
/// Mirrors [`LlmReadinessPhase`](llm_readiness_state.dart) one-for-one
/// — the two cubits share a downloader; only the spec they pass and
/// the user-facing copy differ. Keeping them as separate enums (rather
/// than one shared `ReadinessPhase`) lets a single screen depend on
/// both without ambiguous type contexts.
enum WhisperReadinessPhase {
  /// No model on disk and the user has not opted in.
  idle,

  /// Bytes are streaming to the partial sidecar.
  downloading,

  /// Download finished; SHA-256 verification in progress.
  verifying,

  /// The canonical file is on disk and verified.
  ready,

  /// Network error / hash mismatch / disk full. `failureReason` carries
  /// the user-visible message.
  failed,
}

/// State for [`WhisperReadinessCubit`](whisper_readiness_cubit.dart).
/// The phase + the two byte counts + `failureReason` are the entire UI
/// surface — anything richer (per-byte throughput, ETAs) belongs to the
/// cubit's internals, not the state.
class WhisperReadinessState extends Equatable {
  const WhisperReadinessState({
    required this.phase,
    this.progressBytes = 0,
    this.totalBytes = 0,
    this.failureReason,
  });

  /// Initial state — no model, no opt-in. Cubit constructor seeds this.
  const WhisperReadinessState.idle()
      : phase = WhisperReadinessPhase.idle,
        progressBytes = 0,
        totalBytes = 0,
        failureReason = null;

  final WhisperReadinessPhase phase;
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

  WhisperReadinessState copyWith({
    WhisperReadinessPhase? phase,
    int? progressBytes,
    int? totalBytes,
    String? failureReason,
    bool clearFailureReason = false,
  }) {
    return WhisperReadinessState(
      phase: phase ?? this.phase,
      progressBytes: progressBytes ?? this.progressBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      failureReason: clearFailureReason ? null : (failureReason ?? this.failureReason),
    );
  }

  @override
  List<Object?> get props => [phase, progressBytes, totalBytes, failureReason];
}
