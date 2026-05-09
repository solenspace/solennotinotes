import 'dart:async';

/// Stub contract for the on-device large-language-model runtime that backs
/// Phase 5 (Specs 19–21). Spec 18 lands the interface; Spec 19 ships the
/// concrete implementation against the binding selected by the
/// `tools/llm-validation/` benchmark harness (architecture decision #6, to
/// be finalised as decision #32 once empirical numbers land — #31 is taken
/// by Spec 17's `RecordingNoteEditorBloc` structural fix).
///
/// Implementers must honour these invariants from `architecture.md`:
///
///  * **Invariant 1 (zero network).** The chosen binding loads only local
///    GGUF files; no transitive HTTP / cloud SDK imports may reach `lib/`.
///    Any package that sneaks one in fails the offline gate
///    (`scripts/check-offline.sh`) and is disqualified from Spec 18 by
///    construction.
///  * **Invariant 2 (AI is device-gated).** Every entry point that calls
///    [load] / [generate] must first consult `DeviceCapabilityService.aiTier`
///    and short-circuit on `AiTier.unsupported`. The runtime itself is
///    tier-blind by design — gating happens one layer up.
///  * **Invariant 8 (cancellable async).** Subscribers cancel a generation
///    by calling `subscription.cancel()` on the [generate] stream; the
///    implementation MUST stop sampling within one token of cancel and
///    release any C-side context. Long-running [load] calls similarly
///    cooperate with `Bloc.close()` lifecycles.
///  * **Invariant 10 (no bundled model).** [load] resolves a model file
///    written into the platform application-support directory by Spec 19's
///    download flow. The runtime never reads from the asset bundle.
///
/// The interface is intentionally minimal: a single `Stream<String>` of
/// token chunks is the contract Spec 18 locked, mirroring the streaming
/// callbacks every candidate binding exposes. Future phases may evolve
/// this into a sealed `LlmEvent` (parity with `TtsEvent` /
/// `SttRecognitionEvent`) once concrete error paths are mapped — that
/// evolution is out of scope for Spec 18.
abstract class LlmRuntime {
  /// Loads the GGUF model at [modelPath] into memory and returns whether
  /// the runtime is ready to [generate]. A `false` return signals a
  /// recoverable load failure (file missing, OOM, format mismatch); the
  /// caller may retry with a different model. Implementations propagate
  /// genuinely fatal native errors as exceptions.
  ///
  /// Calling [load] while [isLoaded] is `true` MUST [unload] the previous
  /// model before swapping; the runtime never holds two contexts at once.
  Future<bool> load({required String modelPath});

  /// Streams generated tokens as they arrive from the sampler. The stream
  /// emits one event per token chunk (per the streaming criterion in Spec
  /// 18 §"Validation criteria") and closes when generation finishes,
  /// `maxTokens` is reached, the subscription is cancelled, or [unload] is
  /// called. Errors surface via the stream's error channel.
  ///
  /// `temperature` is the sampler temperature in `[0.0, 2.0]`; values
  /// outside that range are clamped by the implementation. The runtime
  /// rejects calls when [isLoaded] is `false` by emitting a `StateError`
  /// on the stream and closing.
  Stream<String> generate({
    required String prompt,
    int maxTokens = 256,
    double temperature = 0.7,
  });

  /// Releases the loaded model and any native context. Idempotent: calling
  /// [unload] when [isLoaded] is `false` is a no-op. After this resolves
  /// [isLoaded] is `false` and a subsequent [load] starts from a cold
  /// context.
  Future<void> unload();

  bool get isLoaded;
}
