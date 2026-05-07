import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/ai/llm_model_downloader.dart';
import 'llm_readiness_state.dart';

/// Owns the AI-assist row's lifecycle: probe disk on construction (so the
/// row reflects "ready" immediately on app start when the file is already
/// there), kick off downloads on user opt-in, and cancel cleanly when the
/// user backs out mid-stream.
///
/// Mounted by `lib/features/settings/screen.dart` rather than at app root
/// (per Spec 19 § F) so the cubit's lifecycle matches the AI-settings
/// surface — opening / closing the screen builds and disposes the cubit.
class LlmReadinessCubit extends Cubit<LlmReadinessState> {
  LlmReadinessCubit({required LlmModelDownloader downloader})
      : _downloader = downloader,
        super(const LlmReadinessState.idle());

  final LlmModelDownloader _downloader;
  StreamSubscription<DownloadProgress>? _downloadSub;

  /// Probe the application-support directory for an already-verified model
  /// file. Idempotent — calling it twice on a freshly-launched cubit is a
  /// no-op the second time around. Settings screen invokes this in its
  /// `BlocProvider.create` so the row paints "AI assist enabled" on first
  /// frame for users who already downloaded on a previous run.
  Future<void> bootstrap() async {
    if (state.phase != LlmReadinessPhase.idle) return;
    if (await _downloader.isAlreadyDownloaded()) {
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

    _downloadSub = _downloader.download().listen(
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
    await _downloader.deletePartial();
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
