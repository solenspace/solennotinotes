import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/ai/model_download_spec.dart';
import '../../../services/ai/model_downloader.dart';
import '../../../services/ai/whisper_model_constants.dart';
import '../../../services/device/ai_tier.dart';
import 'whisper_readiness_state.dart';

/// Owns the voice-transcription row's lifecycle (Spec 21): probe disk
/// on construction (so the row reflects "ready" immediately on app
/// start when the file is already there), kick off downloads on user
/// opt-in, and cancel cleanly when the user backs out mid-stream.
///
/// Hoisted at the app shell next to [`LlmReadinessCubit`] so both the
/// settings tile and the editor's audio-block "Transcribe" menu read
/// the same readiness signal without redundant disk probes. The
/// underlying [ModelDownloader] is shared with the LLM sibling cubit;
/// each cubit injects its own [ModelDownloadSpec] so the downloader
/// stays model-agnostic.
///
/// Tier-driven variant selection (architecture decision #7) is resolved
/// at construction: `AiTier.full → whisper-base.en`,
/// `AiTier.compact → whisper-tiny.en`. The tier is read once because a
/// re-probe mid-session would require restarting any in-flight
/// download anyway — the conservative posture (`reprobe()` on cold
/// start only) is documented in `device_capability_service.dart`.
class WhisperReadinessCubit extends Cubit<WhisperReadinessState> {
  /// [tier] selects the Whisper variant via
  /// [WhisperModelConstants.specForTier]. Callers must pre-check
  /// `tier.canRunWhisper`; passing [AiTier.unsupported] throws
  /// (defence-in-depth — UI gates already short-circuit).
  WhisperReadinessCubit({
    required ModelDownloader downloader,
    required AiTier tier,
  })  : _downloader = downloader,
        _spec = WhisperModelConstants.specForTier(tier),
        super(const WhisperReadinessState.idle());

  final ModelDownloader _downloader;
  final ModelDownloadSpec _spec;

  /// The frozen spec this cubit owns. Exposed so the Manage AI screen
  /// can read filename / size / version for the model-info card
  /// without re-deriving from tier.
  ModelDownloadSpec get spec => _spec;

  StreamSubscription<DownloadProgress>? _downloadSub;

  /// Probe the application-support directory for an already-verified
  /// model file. Idempotent — calling it twice on a freshly-launched
  /// cubit is a no-op the second time around.
  Future<void> bootstrap() async {
    if (state.phase != WhisperReadinessPhase.idle) return;
    if (await _downloader.isAlreadyDownloaded(_spec)) {
      emit(const WhisperReadinessState(phase: WhisperReadinessPhase.ready));
    }
  }

  /// Begin (or retry) the download. Cancels any in-flight subscription
  /// first so calling `start()` while already downloading is harmless.
  Future<void> start() async {
    await _downloadSub?.cancel();
    emit(
      state.copyWith(
        phase: WhisperReadinessPhase.downloading,
        progressBytes: 0,
        totalBytes: 0,
        clearFailureReason: true,
      ),
    );

    _downloadSub = _downloader.download(_spec).listen(
          _onProgress,
          onError: _onStreamError,
        );
  }

  void _onProgress(DownloadProgress progress) {
    switch (progress) {
      case DownloadingProgress(:final bytes, :final total):
        emit(
          state.copyWith(
            phase: WhisperReadinessPhase.downloading,
            progressBytes: bytes,
            totalBytes: total,
          ),
        );
      case VerifyingProgress():
        emit(state.copyWith(phase: WhisperReadinessPhase.verifying));
      case ReadyProgress():
        emit(
          state.copyWith(
            phase: WhisperReadinessPhase.ready,
            clearFailureReason: true,
          ),
        );
      case FailedProgress(:final reason):
        emit(
          state.copyWith(
            phase: WhisperReadinessPhase.failed,
            failureReason: reason,
          ),
        );
    }
  }

  void _onStreamError(Object error, StackTrace _) {
    emit(
      state.copyWith(
        phase: WhisperReadinessPhase.failed,
        failureReason: _humanise(error),
      ),
    );
  }

  /// User-initiated cancel. Cancels the subscription, deletes the
  /// partial sidecar (so the next `start()` is a fresh download, not a
  /// resume — users hitting Cancel are signalling intent, not a
  /// transient hiccup), and returns the row to `idle`.
  Future<void> cancel() async {
    await _downloadSub?.cancel();
    _downloadSub = null;
    await _downloader.deletePartial(_spec);
    emit(const WhisperReadinessState.idle());
  }

  /// Disable transcription by deleting the verified model + any
  /// partial sidecar. Used by the Manage AI screen when the user
  /// chooses "Delete model and disable transcription". Returns the row
  /// to `idle` so re-enabling goes through the disclosure sheet again.
  Future<void> disable() async {
    await _downloadSub?.cancel();
    _downloadSub = null;
    await _downloader.deleteAll(_spec);
    emit(const WhisperReadinessState.idle());
  }

  @override
  Future<void> close() async {
    await _downloadSub?.cancel();
    return super.close();
  }

  static String _humanise(Object error) {
    if (error is FormatException) return error.message;
    return error.toString();
  }
}
