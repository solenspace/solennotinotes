import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/ai/llm_model_constants.dart';
import '../../../services/ai/model_download_spec.dart';
import '../../../services/ai/model_downloader.dart';
import 'llm_readiness_state.dart';

/// Owns the AI-assist row's lifecycle: probe disk on construction (so the
/// row reflects "ready" immediately on app start when the file is already
/// there), kick off downloads on user opt-in, and cancel cleanly when the
/// user backs out mid-stream.
///
/// Hoisted at the app shell (Spec 20 § "Hoist LlmReadinessCubit") so both
/// the settings tile and the editor's ✦ Assist button share a single
/// readiness signal without redundant disk probes.
///
/// The downloader instance is shared with `WhisperReadinessCubit` (Spec
/// 21); this cubit always passes [LlmModelConstants.spec] to its
/// methods, while the Whisper sibling passes its own spec — the
/// downloader stays model-agnostic.
class LlmReadinessCubit extends Cubit<LlmReadinessState> {
  LlmReadinessCubit({
    required ModelDownloader downloader,
    ModelDownloadSpec spec = LlmModelConstants.spec,
  })  : _downloader = downloader,
        _spec = spec,
        super(const LlmReadinessState.idle());

  final ModelDownloader _downloader;
  final ModelDownloadSpec _spec;
  StreamSubscription<DownloadProgress>? _downloadSub;

  /// Probe the application-support directory for an already-verified model
  /// file. Idempotent — calling it twice on a freshly-launched cubit is a
  /// no-op the second time around. Settings screen invokes this in its
  /// `BlocProvider.create` so the row paints "AI assist enabled" on first
  /// frame for users who already downloaded on a previous run.
  Future<void> bootstrap() async {
    if (state.phase != LlmReadinessPhase.idle) return;
    if (await _downloader.isAlreadyDownloaded(_spec)) {
      emit(const LlmReadinessState(phase: LlmReadinessPhase.ready));
    }
  }

  /// Begin (or retry) the download. Cancels any in-flight subscription
  /// first so calling `start()` while already downloading is harmless.
  Future<void> start() async {
    await _downloadSub?.cancel();
    emit(
      state.copyWith(
        phase: LlmReadinessPhase.downloading,
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
            phase: LlmReadinessPhase.downloading,
            progressBytes: bytes,
            totalBytes: total,
          ),
        );
      case VerifyingProgress():
        emit(state.copyWith(phase: LlmReadinessPhase.verifying));
      case ReadyProgress():
        emit(
          state.copyWith(
            phase: LlmReadinessPhase.ready,
            clearFailureReason: true,
          ),
        );
      case FailedProgress(:final reason):
        emit(
          state.copyWith(
            phase: LlmReadinessPhase.failed,
            failureReason: reason,
          ),
        );
    }
  }

  void _onStreamError(Object error, StackTrace _) {
    emit(
      state.copyWith(
        phase: LlmReadinessPhase.failed,
        failureReason: _humanise(error),
      ),
    );
  }

  /// User-initiated cancel. Cancels the subscription, deletes the partial
  /// sidecar (so the next `start()` is a fresh download, not a resume —
  /// users hitting Cancel are signalling intent, not a transient hiccup),
  /// and returns the row to `idle`.
  Future<void> cancel() async {
    await _downloadSub?.cancel();
    _downloadSub = null;
    await _downloader.deletePartial(_spec);
    emit(const LlmReadinessState.idle());
  }

  /// Disable AI assist by deleting the verified model + any partial
  /// sidecar. Used by `ManageAiScreen` (Spec 20 § G) when the user
  /// chooses "Delete model and disable AI". Returns the row to `idle`
  /// so re-enabling goes through the disclosure sheet again.
  Future<void> disable() async {
    await _downloadSub?.cancel();
    _downloadSub = null;
    await _downloader.deleteAll(_spec);
    emit(const LlmReadinessState.idle());
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
