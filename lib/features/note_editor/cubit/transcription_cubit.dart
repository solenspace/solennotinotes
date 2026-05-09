import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:noti_notes_app/services/ai/whisper_runtime.dart';

import 'transcription_state.dart';

/// Per-audio-block cubit that drives the transcription overlay (Spec
/// 21). Created when the user taps "Transcribe" in the audio block's
/// long-press menu, disposed when the overlay closes (Insert below /
/// Replace audio / Discard / Cancel).
///
/// Lifecycle:
///
///   * The runtime is **shared** at the app shell via
///     `RepositoryProvider<WhisperRuntime>` (see `main.dart`). The cubit
///     does **not** call [`WhisperRuntime.unload`] in `close()` —
///     unloading would burn the worker isolate every time the user
///     transcribes one audio block, only to re-spawn on the next.
///     `dispose` on the `RepositoryProvider` handles teardown when the
///     app exits.
///   * Lazy-load: the runtime's model is loaded on the first `start`,
///     mirroring [`AiAssistCubit`](ai_assist_cubit.dart). Editor
///     sessions that never touch transcription pay zero load cost.
///   * Cancellation: cancelling the in-flight stream subscription
///     posts a stop command to the worker isolate; the worker aborts
///     within one Whisper segment (invariant 8). The cubit emits
///     `phase: idle` so the overlay can dismiss cleanly.
class TranscriptionCubit extends Cubit<TranscriptionState> {
  TranscriptionCubit({
    required WhisperRuntime runtime,
    required Future<String> Function() modelPathResolver,
  })  : _runtime = runtime,
        _modelPathResolver = modelPathResolver,
        super(const TranscriptionState());

  final WhisperRuntime _runtime;
  final Future<String> Function() _modelPathResolver;

  StreamSubscription<TranscriptionEvent>? _sub;

  /// Begin a transcription for [audioFilePath]. Idempotent against
  /// rapid double-taps: while a transcription is in flight, additional
  /// [start] calls are ignored.
  Future<void> start(String audioFilePath) async {
    if (state.phase == TranscriptionPhase.running) return;

    emit(
      state.copyWith(
        phase: TranscriptionPhase.running,
        progress: 0.0,
        result: '',
        clearError: true,
      ),
    );

    if (!_runtime.isLoaded) {
      try {
        final modelPath = await _modelPathResolver();
        final loaded = await _runtime.load(modelPath: modelPath);
        if (!loaded) {
          emit(
            state.copyWith(
              phase: TranscriptionPhase.failed,
              errorMessage: 'The on-device Whisper model could not be loaded.',
            ),
          );
          return;
        }
      } catch (e) {
        emit(
          state.copyWith(
            phase: TranscriptionPhase.failed,
            errorMessage: _humanise(e),
          ),
        );
        return;
      }
    }

    _sub = _runtime.transcribe(audioFilePath: audioFilePath).listen(
          _onEvent,
          onError: _onError,
          onDone: _onDone,
          cancelOnError: true,
        );
  }

  void _onEvent(TranscriptionEvent event) {
    switch (event) {
      case TranscriptionProgress(:final fraction):
        // Clamp to defensively guard against out-of-range native
        // emissions; the overlay's progress bar would otherwise glitch.
        final clamped = fraction.clamp(0.0, 1.0);
        emit(state.copyWith(progress: clamped));
      case TranscriptionResult(:final text):
        emit(
          state.copyWith(
            phase: TranscriptionPhase.ready,
            result: text.trim(),
            progress: 1.0,
          ),
        );
    }
  }

  void _onError(Object error, StackTrace _) {
    emit(
      state.copyWith(
        phase: TranscriptionPhase.failed,
        errorMessage: _humanise(error),
      ),
    );
  }

  void _onDone() {
    // If the stream closed without a TranscriptionResult — e.g. the
    // worker errored after sending Done but before the result, or a
    // cancellation race — and we're still in `running`, fall through
    // to `failed`. Ready/idle/failed are terminal; don't perturb.
    if (state.phase == TranscriptionPhase.running) {
      emit(
        state.copyWith(
          phase: TranscriptionPhase.failed,
          errorMessage: 'Transcription finished without producing a result.',
        ),
      );
    }
  }

  /// User-initiated cancel. Cancels the subscription, returns to idle.
  /// Idempotent.
  Future<void> cancel() async {
    await _sub?.cancel();
    _sub = null;
    emit(const TranscriptionState());
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    // Intentional: do NOT unload the shared runtime here. The
    // `RepositoryProvider<WhisperRuntime>` in `main.dart` handles
    // teardown via its `dispose` callback at app exit; per-cubit
    // unload would force a model reload on every "Transcribe" tap.
    return super.close();
  }

  static String _humanise(Object error) {
    if (error is StateError) return error.message;
    return error.toString();
  }
}
