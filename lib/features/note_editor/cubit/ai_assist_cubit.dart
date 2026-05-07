import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import 'package:noti_notes_app/services/ai/ai_action.dart';
import 'package:noti_notes_app/services/ai/llm_runtime.dart';
import 'package:noti_notes_app/services/ai/prompts.dart';

import 'ai_assist_state.dart';

/// Per-editor-route cubit that drives the AI assist bottom sheet. Owns
/// the generation lifecycle (load → stream → accept / discard) and
/// frees the underlying [LlmRuntime] when the route disposes.
///
/// Architectural responsibilities:
///
///   * The cubit never imports widgets and never calls the
///     `NotesRepository` directly; mutations to the note flow through
///     `NoteEditorBloc` events dispatched by the sheet (Spec 20 §
///     "Result handling — accept paths"). This keeps the audit trail
///     coherent and respects the BLoC ↔ widget direction in
///     `code-standards.md`.
///   * Generation is lazy: the model is only loaded when the user runs
///     their first action. This means the first action carries the
///     ~5–10s load latency, but the alternative — preloading on every
///     editor open — would burn memory on note-edit sessions that never
///     touch AI.
///   * Cancellation honours the [LlmRuntime] contract: calling
///     `subscription.cancel()` stops sampling within one token. The
///     cubit retains the partial output so the user can still accept a
///     half-finished draft, matching Spec 20's stop semantics
///     ("partial output discarded" only on explicit Discard).
class AiAssistCubit extends Cubit<AiAssistState> {
  AiAssistCubit({
    required LlmRuntime runtime,
    required Future<String> Function() modelPathResolver,
  })  : _runtime = runtime,
        _modelPathResolver = modelPathResolver,
        super(const AiAssistState.initial());

  /// Test-only seam: lets widget tests put the cubit into a streaming
  /// or finished state without driving the runtime + Timer + subscription
  /// chain through a fake clock. Production code paths (`start` / `stop`
  /// / `reset`) handle the lifecycle for end users; only call this from
  /// test setup.
  @visibleForTesting
  void debugEmit(AiAssistState state) => emit(state);

  final LlmRuntime _runtime;
  final Future<String> Function() _modelPathResolver;

  StreamSubscription<String>? _genSub;
  Timer? _elapsedTimer;
  Stopwatch? _watch;

  /// Begin a generation for [action] using [noteText] as the prompt
  /// payload. Idempotent against rapid double-taps: while a generation
  /// is in flight, additional [start] calls are ignored.
  Future<void> start({
    required AiAction action,
    required String noteText,
  }) async {
    if (state.isGenerating) return;

    emit(
      AiAssistState(
        activeAction: action,
        isGenerating: true,
        elapsed: Duration.zero,
      ),
    );

    if (!_runtime.isLoaded) {
      try {
        final modelPath = await _modelPathResolver();
        final loaded = await _runtime.load(modelPath: modelPath);
        if (!loaded) {
          emit(
            state.copyWith(
              isGenerating: false,
              finished: true,
              errorMessage: 'The on-device model could not be loaded.',
            ),
          );
          return;
        }
      } catch (e) {
        emit(
          state.copyWith(
            isGenerating: false,
            finished: true,
            errorMessage: _humanise(e),
          ),
        );
        return;
      }
    }

    _watch = Stopwatch()..start();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final w = _watch;
      if (w == null) return;
      emit(state.copyWith(elapsed: w.elapsed));
    });

    final prompt = AiPrompts.build(action, noteText);
    _genSub = _runtime.generate(prompt: prompt).listen(
          _onToken,
          onError: _onError,
          onDone: _onDone,
          cancelOnError: true,
        );
  }

  /// User-initiated stop. Cancels the stream subscription (which
  /// signals the runtime to stop sampling) and freezes the partial
  /// output as the result. Idempotent.
  Future<void> stop() async {
    if (!state.isGenerating) return;
    await _genSub?.cancel();
    _genSub = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _watch?.stop();
    emit(
      state.copyWith(
        isGenerating: false,
        finished: true,
        elapsed: _watch?.elapsed ?? state.elapsed,
      ),
    );
    _watch = null;
  }

  /// Reset to the picker view. Clears [AiAssistState.draftOutput] per
  /// Spec 20 § "Privacy reinforcement" — generated text never lingers
  /// in cubit memory after the user has accepted or dismissed it.
  void reset() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _watch = null;
    emit(const AiAssistState.initial());
  }

  void _onToken(String chunk) {
    emit(
      state.copyWith(
        draftOutput: state.draftOutput + chunk,
        firstTokenArrived: true,
        elapsed: _watch?.elapsed ?? state.elapsed,
      ),
    );
  }

  void _onError(Object error, StackTrace _) {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _watch?.stop();
    emit(
      state.copyWith(
        isGenerating: false,
        finished: true,
        errorMessage: _humanise(error),
        elapsed: _watch?.elapsed ?? state.elapsed,
      ),
    );
    _watch = null;
  }

  void _onDone() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _watch?.stop();
    emit(
      state.copyWith(
        isGenerating: false,
        finished: true,
        elapsed: _watch?.elapsed ?? state.elapsed,
      ),
    );
    _watch = null;
  }

  static String _humanise(Object error) {
    if (error is StateError) return error.message;
    return error.toString();
  }

  @override
  Future<void> close() async {
    await _genSub?.cancel();
    _genSub = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _watch?.stop();
    _watch = null;
    await _runtime.unload();
    return super.close();
  }
}
