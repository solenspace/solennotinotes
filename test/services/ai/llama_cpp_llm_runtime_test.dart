import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/services/ai/llama_cpp_llm_runtime.dart';

/// Contract tests for [LlamaCppLlmRuntime] that don't require a real GGUF
/// file. The "happy path" (load → generate → unload against a real model)
/// is exercised by the manual smoke per Spec 20 § "Success Criteria".
///
/// What these tests cover:
///
///   * `generate` before `load` reports a `StateError` on the stream
///     instead of silently hanging.
///   * `unload` is idempotent — calling it before any `load`, and then
///     calling it again, must not throw.
///   * `isLoaded` is `false` initially.
///
/// Loading a real model requires a 600 MB GGUF + a vendored llama.cpp
/// shared library, which the CI host does not have; the contract above
/// is what we can verify deterministically without those assets.
void main() {
  group('LlamaCppLlmRuntime contract', () {
    test('isLoaded is false initially', () {
      final runtime = LlamaCppLlmRuntime();
      expect(runtime.isLoaded, isFalse);
    });

    test('generate before load surfaces a StateError', () async {
      final runtime = LlamaCppLlmRuntime();
      final stream = runtime.generate(prompt: 'hi');
      await expectLater(stream, emitsError(isA<StateError>()));
    });

    test('unload before load is a no-op', () async {
      final runtime = LlamaCppLlmRuntime();
      await runtime.unload();
      expect(runtime.isLoaded, isFalse);
      // Calling again must remain a no-op.
      await runtime.unload();
      expect(runtime.isLoaded, isFalse);
    });
  });
}
