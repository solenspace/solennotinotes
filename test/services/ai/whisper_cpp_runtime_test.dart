import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/services/ai/whisper_cpp_runtime.dart';

/// Contract tests for [WhisperCppRuntime] that do **not** require a
/// loaded native model. These mirror the LLM contract tests in
/// `llama_cpp_llm_runtime_test.dart` and exercise only the pure-Dart
/// invariants of the runtime: lifecycle flags, error paths before
/// load, idempotent unload.
///
/// The full load + transcribe happy path requires the chosen Whisper
/// model on disk + the wired native binding (per Spec 21 § Agents,
/// `flutter-expert` validates this); it is exercised by the spec's
/// manual smoke checklist.
void main() {
  group('WhisperCppRuntime', () {
    test('isLoaded is false on a freshly-constructed instance', () {
      final runtime = WhisperCppRuntime();
      expect(runtime.isLoaded, isFalse);
    });

    test('transcribe() before load() emits a StateError on the stream', () async {
      final runtime = WhisperCppRuntime();
      final stream = runtime.transcribe(audioFilePath: '/tmp/missing.m4a');
      Object? error;
      await stream.handleError((Object e, StackTrace _) {
        error = e;
      }).drain<void>();
      expect(error, isA<StateError>());
    });

    test('unload() is idempotent on a never-loaded runtime', () async {
      final runtime = WhisperCppRuntime();
      // Two calls in a row must not throw.
      await runtime.unload();
      await runtime.unload();
      expect(runtime.isLoaded, isFalse);
    });
  });
}
