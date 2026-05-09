import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/note_editor/cubit/transcription_cubit.dart';
import 'package:noti_notes_app/features/note_editor/cubit/transcription_state.dart';
import 'package:noti_notes_app/services/ai/whisper_runtime.dart';

import '../../../services/ai/fake_whisper_runtime.dart';

/// Drains [expectedAtLeast] emissions from [cubit] while [act] runs,
/// with a short polling timeout. Mirrors the helper in
/// `ai_assist_cubit_test.dart`.
Future<List<TranscriptionState>> _drain(
  TranscriptionCubit cubit,
  Future<void> Function() act, {
  required int expectedAtLeast,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final emissions = <TranscriptionState>[];
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
  late FakeWhisperRuntime fake;
  late TranscriptionCubit cubit;

  setUp(() {
    fake = FakeWhisperRuntime();
    cubit = TranscriptionCubit(
      runtime: fake,
      modelPathResolver: () async => '/fake/whisper-base.en.bin',
    );
  });

  tearDown(() async {
    await cubit.close();
    await fake.dispose();
  });

  group('TranscriptionCubit', () {
    test('starts idle', () {
      expect(cubit.state.phase, TranscriptionPhase.idle);
      expect(cubit.state.progress, 0.0);
      expect(cubit.state.result, '');
      expect(cubit.state.errorMessage, isNull);
    });

    test('happy path: load → progress → result → ready', () async {
      fake.scriptedEvents = const [
        TranscriptionProgress(0.25),
        TranscriptionProgress(0.75),
        TranscriptionResult('hello world'),
      ];
      final emissions = await _drain(
        cubit,
        () => cubit.start('/audio.m4a'),
        expectedAtLeast: 4,
      );
      // Initial running emission + 2 progress + 1 result.
      expect(emissions.first.phase, TranscriptionPhase.running);
      expect(fake.loadCalls, 1);
      expect(fake.lastModelPath, '/fake/whisper-base.en.bin');
      expect(fake.lastAudioFilePath, '/audio.m4a');
      expect(cubit.state.phase, TranscriptionPhase.ready);
      expect(cubit.state.result, 'hello world');
      expect(cubit.state.progress, 1.0);
    });

    test('clamps progress fractions to [0.0, 1.0]', () async {
      await cubit.start('/audio.m4a');
      // Load + initial-emit happen synchronously inside start; allow
      // microtasks to drain.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      fake.emitProgress(-0.5);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cubit.state.progress, 0.0);
      fake.emitProgress(2.0);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cubit.state.progress, 1.0);
    });

    test('lazy-loads on first start; second start skips reload', () async {
      fake.scriptedEvents = const [TranscriptionResult('a')];
      await cubit.start('/audio.m4a');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(fake.loadCalls, 1);

      // Reset cubit state via cancel and re-run start. Runtime stays
      // loaded, so load() is not called a second time.
      await cubit.cancel();
      fake.scriptedEvents = const [TranscriptionResult('b')];
      await cubit.start('/audio.m4a');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(fake.loadCalls, 1);
      expect(fake.transcribeCalls, 2);
    });

    test('load returning false surfaces failed phase', () async {
      fake.loadResult = false;
      await cubit.start('/audio.m4a');
      // start() awaits load before emitting; one microtask is enough.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cubit.state.phase, TranscriptionPhase.failed);
      expect(cubit.state.errorMessage, isNotNull);
      expect(fake.transcribeCalls, 0);
    });

    test('load throwing surfaces failed phase with humanised message', () async {
      fake.loadThrows = StateError('out of memory');
      await cubit.start('/audio.m4a');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cubit.state.phase, TranscriptionPhase.failed);
      expect(cubit.state.errorMessage, contains('out of memory'));
    });

    test('stream error after load surfaces failed phase', () async {
      await cubit.start('/audio.m4a');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      fake.emitError(const FormatException('decode failed'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cubit.state.phase, TranscriptionPhase.failed);
      expect(cubit.state.errorMessage, contains('decode failed'));
    });

    test('cancel mid-stream returns to idle and signals worker', () async {
      await cubit.start('/audio.m4a');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      fake.emitProgress(0.4);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(cubit.state.phase, TranscriptionPhase.running);

      await cubit.cancel();

      expect(cubit.state.phase, TranscriptionPhase.idle);
      expect(cubit.state.progress, 0.0);
      expect(fake.activeStreamCancelled, isTrue);
    });

    test('double-start while running is ignored', () async {
      await cubit.start('/audio.m4a');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(fake.transcribeCalls, 1);
      await cubit.start('/audio.m4a');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(fake.transcribeCalls, 1);
    });

    test('stream closing without result emits failed', () async {
      await cubit.start('/audio.m4a');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await fake.completeTranscription();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(cubit.state.phase, TranscriptionPhase.failed);
      expect(cubit.state.errorMessage, isNotNull);
    });

    test('close() does not unload the (shared) runtime', () async {
      await cubit.start('/audio.m4a');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await cubit.close();
      // The shared runtime stays alive — `RepositoryProvider` handles
      // teardown at app exit.
      expect(fake.unloadCalls, 0);
    });
  });
}
