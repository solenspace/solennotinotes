import 'package:equatable/equatable.dart';

/// Phase of a per-audio-block transcription session.
enum TranscriptionPhase {
  /// No transcription has been started, or the previous one was
  /// cancelled / discarded.
  idle,

  /// The native runtime is loading and/or processing audio. The
  /// `progress` field carries 0..1 fraction.
  running,

  /// Transcription completed; `result` carries the trimmed transcript
  /// awaiting the user's Insert / Replace / Discard choice.
  ready,

  /// Native runtime failed (load error, decode error, OOM); the
  /// overlay surfaces `errorMessage` + Try-again / Discard buttons.
  failed,
}

/// Equatable state for [`TranscriptionCubit`](transcription_cubit.dart).
class TranscriptionState extends Equatable {
  const TranscriptionState({
    this.phase = TranscriptionPhase.idle,
    this.progress = 0.0,
    this.result = '',
    this.errorMessage,
  });

  final TranscriptionPhase phase;
  final double progress;
  final String result;
  final String? errorMessage;

  TranscriptionState copyWith({
    TranscriptionPhase? phase,
    double? progress,
    String? result,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TranscriptionState(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      result: result ?? this.result,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [phase, progress, result, errorMessage];
}
