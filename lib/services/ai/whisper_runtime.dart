import 'dart:async';

/// Stub contract for the on-device Whisper transcription runtime that
/// backs Spec 21. The interface lives here; the concrete implementation
/// in `whisper_cpp_runtime.dart` wires the chosen Whisper.cpp Dart
/// binding behind a worker isolate, mirroring the LLM split established
/// in Specs 18 + 20 (`llm_runtime.dart` ↔ `llama_cpp_llm_runtime.dart`).
///
/// Implementers must honour these invariants from `architecture.md`:
///
///  * **Invariant 1 (zero network).** The chosen binding loads only
///    local model files; no transitive HTTP / cloud SDK imports may
///    reach `lib/`. Any package that sneaks one in fails the offline
///    gate (`scripts/check-offline.sh`) and is disqualified by
///    construction.
///  * **Invariant 2 (AI is device-gated).** Every entry point that calls
///    [load] / [transcribe] must first consult
///    `DeviceCapabilityService.aiTier.canRunWhisper` and short-circuit on
///    `AiTier.unsupported`. The runtime itself is tier-blind by design —
///    gating happens one layer up.
///  * **Invariant 8 (cancellable async).** Subscribers cancel a
///    transcription by calling `subscription.cancel()` on the
///    [transcribe] stream; the implementation MUST stop sampling within
///    one Whisper segment of cancel and release any C-side context.
///    Long-running [load] calls similarly cooperate with `Bloc.close()`
///    lifecycles.
///  * **Invariant 10 (no bundled model).** [load] resolves a model file
///    written into the platform application-support directory by Spec
///    21's download flow (under `<app_support>/whisper/`). The runtime
///    never reads from the asset bundle.
///
/// The streamed event channel is sealed so callers can `switch` over
/// concrete subtypes exhaustively. Whisper.cpp produces whole-segment
/// outputs (not token-by-token like an LLM), so [TranscriptionProgress]
/// carries only a coarse fraction; the full transcript is delivered as
/// a single terminal [TranscriptionResult] right before the stream
/// closes.
abstract class WhisperRuntime {
  /// Loads the model file at [modelPath] into memory and returns whether
  /// the runtime is ready to [transcribe]. A `false` return signals a
  /// recoverable load failure (file missing, OOM, format mismatch); the
  /// caller may retry with a different model. Implementations propagate
  /// genuinely fatal native errors as exceptions.
  ///
  /// Calling [load] while [isLoaded] is `true` MUST [unload] the
  /// previous model before swapping; the runtime never holds two
  /// contexts at once.
  Future<bool> load({required String modelPath});

  /// Streams [TranscriptionEvent]s for the audio at [audioFilePath].
  /// Emits zero-or-more [TranscriptionProgress] events as Whisper
  /// processes chunks, then exactly one [TranscriptionResult] before
  /// closing. Errors surface via the stream's error channel.
  ///
  /// The runtime rejects calls when [isLoaded] is `false` by emitting a
  /// `StateError` on the stream and closing.
  ///
  /// Cancellation: cancelling the subscription triggers the worker to
  /// abort within one Whisper segment (~30 s of audio at most;
  /// typically much sooner) and frees its segment-callback state.
  Stream<TranscriptionEvent> transcribe({required String audioFilePath});

  /// Releases the loaded model and any native context. Idempotent:
  /// calling [unload] when [isLoaded] is `false` is a no-op. After this
  /// resolves [isLoaded] is `false` and a subsequent [load] starts from
  /// a cold context.
  Future<void> unload();

  bool get isLoaded;
}

/// Sealed event hierarchy emitted by [WhisperRuntime.transcribe]. The
/// stream emits a sequence of [TranscriptionProgress] (each with a
/// monotonically non-decreasing `fraction` in `[0.0, 1.0]`) followed by
/// exactly one [TranscriptionResult] before closing. Callers should
/// `switch` exhaustively over the two concrete types.
sealed class TranscriptionEvent {
  const TranscriptionEvent();
}

/// Progress signal — `fraction` is the share of audio processed so far
/// (1.0 means "almost done; result imminent"). Whisper.cpp's segment
/// callback is the natural cadence; chunk-based bindings emit one
/// progress event per chunk.
class TranscriptionProgress extends TranscriptionEvent {
  const TranscriptionProgress(this.fraction);
  final double fraction;
}

/// Terminal result — the full transcript, trimmed of leading/trailing
/// whitespace. Always followed immediately by the stream closing
/// normally.
class TranscriptionResult extends TranscriptionEvent {
  const TranscriptionResult(this.text);
  final String text;
}
