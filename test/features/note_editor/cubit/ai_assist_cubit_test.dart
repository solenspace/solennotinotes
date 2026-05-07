import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/note_editor/cubit/ai_assist_cubit.dart';
import 'package:noti_notes_app/features/note_editor/cubit/ai_assist_state.dart';
import 'package:noti_notes_app/services/ai/ai_action.dart';

import '../../../services/ai/fake_llm_runtime.dart';

/// Drains [expectedAtLeast] emissions from [cubit] while [act] runs,
/// with a short polling timeout. Mirrors the helper in
/// `llm_readiness_cubit_test.dart`.
Future<List<AiAssistState>> _drain(
  AiAssistCubit cubit,
  Future<void> Function() act, {
  required int expectedAtLeast,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final emissions = <AiAssistState>[];
  final sub = cubit.stream.listen(emissions.add);
  await act();
  final stopAt = DateTime.now().add(timeout);
  while (emissions.length < expectedAtLeast && DateTime.now().isBefore(stopAt)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await sub.cancel();
  return emissions;
}

void main() {
  late FakeLlmRuntime runtime;
  late AiAssistCubit cubit;

  setUp(() {
    runtime = FakeLlmRuntime();
    cubit = AiAssistCubit(
      runtime: runtime,
      modelPathResolver: () async => '/tmp/fake.gguf',
    );
  });

  tearDown(() async {
    await cubit.close();
    await runtime.dispose();
  });

  group('AiAssistCubit', () {
    test('starts in initial state', () {
      expect(cubit.state.activeAction, isNull);
      expect(cubit.state.draftOutput, '');
      expect(cubit.state.isGenerating, isFalse);
      expect(cubit.state.finished, isFalse);
      expect(cubit.state.errorMessage, isNull);
    });

    test('start: lazy-loads the runtime, accumulates tokens, finishes', () async {
      runtime.scriptedTokens = ['Hello, ', 'world.'];
      await _drain(
        cubit,
        () => cubit.start(action: AiAction.summarize, noteText: 'note body'),
        expectedAtLeast: 4,
        timeout: const Duration(seconds: 1),
      );

      expect(runtime.loadCalls, 1);
      expect(runtime.lastModelPath, '/tmp/fake.gguf');
      expect(runtime.lastPrompt, contains('note body'));
      expect(cubit.state.activeAction, AiAction.summarize);
      expect(cubit.state.draftOutput, 'Hello, world.');
      expect(cubit.state.isGenerating, isFalse);
      expect(cubit.state.finished, isTrue);
      expect(cubit.state.firstTokenArrived, isTrue);
    });

    test('start does not re-load when the runtime is already loaded', () async {
      runtime.scriptedTokens = ['ok'];
      await cubit.start(action: AiAction.rewrite, noteText: 'body');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      runtime.scriptedTokens = ['ok2'];
      cubit.reset();
      await cubit.start(action: AiAction.rewrite, noteText: 'body2');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(runtime.loadCalls, 1);
      expect(runtime.generateCalls, 2);
    });

    test('start surfaces a load failure as an errorMessage', () async {
      runtime.loadResult = false;
      await cubit.start(action: AiAction.summarize, noteText: 'body');
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(cubit.state.isGenerating, isFalse);
      expect(cubit.state.finished, isTrue);
      expect(cubit.state.errorMessage, isNotNull);
    });

    test('stop mid-stream cancels subscription and freezes partial output', () async {
      await cubit.start(action: AiAction.summarize, noteText: 'body');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      runtime.emitToken('Partial');
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(cubit.state.isGenerating, isTrue);
      expect(cubit.state.draftOutput, 'Partial');

      await cubit.stop();

      expect(cubit.state.isGenerating, isFalse);
      expect(cubit.state.finished, isTrue);
      expect(cubit.state.draftOutput, 'Partial');
      expect(runtime.activeStreamCancelled, isTrue);
    });

    test('stream errors set errorMessage and end generation', () async {
      runtime.scriptedTokens = ['Half'];
      runtime.scriptedError = StateError('boom');
      await cubit.start(action: AiAction.summarize, noteText: 'body');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.isGenerating, isFalse);
      expect(cubit.state.finished, isTrue);
      expect(cubit.state.errorMessage, 'boom');
      expect(cubit.state.draftOutput, 'Half');
    });

    test('reset clears draft and returns to initial state', () async {
      runtime.scriptedTokens = ['x'];
      await cubit.start(action: AiAction.summarize, noteText: 'body');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.draftOutput, isNotEmpty);

      cubit.reset();

      expect(cubit.state.activeAction, isNull);
      expect(cubit.state.draftOutput, '');
      expect(cubit.state.finished, isFalse);
    });

    test('close calls runtime.unload to free the model', () async {
      runtime.scriptedTokens = ['x'];
      await cubit.start(action: AiAction.summarize, noteText: 'body');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await cubit.close();

      expect(runtime.unloadCalls, greaterThanOrEqualTo(1));
    });

    test('double start while generating is ignored', () async {
      await cubit.start(action: AiAction.summarize, noteText: 'body');
      final calls = runtime.generateCalls;

      await cubit.start(action: AiAction.rewrite, noteText: 'other');
      expect(runtime.generateCalls, calls);
    });
  });

  group('AiAssistState.titleSuggestions', () {
    test('parses numbered lines for suggestTitle', () {
      const state = AiAssistState(
        activeAction: AiAction.suggestTitle,
        draftOutput: '1. Alpha\n2) Beta\n3 - Gamma\nignored\n4. Delta\n5. Epsilon',
      );
      expect(state.titleSuggestions, [
        'Alpha',
        'Beta',
        'Gamma',
        'Delta',
        'Epsilon',
      ]);
    });

    test('returns empty for non-suggestTitle actions', () {
      const state = AiAssistState(
        activeAction: AiAction.summarize,
        draftOutput: '1. Alpha\n2. Beta',
      );
      expect(state.titleSuggestions, isEmpty);
    });

    test('skips empty candidates and unparsable lines', () {
      const state = AiAssistState(
        activeAction: AiAction.suggestTitle,
        draftOutput: '1.   \nrandom text\n2. Real title',
      );
      expect(state.titleSuggestions, ['Real title']);
    });
  });
}
