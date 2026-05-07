import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_state.dart';

import '../../../services/ai/fake_llm_model_downloader.dart';

/// Drains [expectedAtLeast] emissions from [cubit] while [act] runs, with a
/// short polling timeout. Mirrors the helper in `theme_cubit_test.dart`;
/// the project keeps tests on raw `flutter_test` until `bloc_test` clears
/// the analyzer-pin chain (progress-tracker open question 13).
Future<List<LlmReadinessState>> _drain(
  LlmReadinessCubit cubit,
  Future<void> Function() act, {
  required int expectedAtLeast,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final emissions = <LlmReadinessState>[];
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
  late FakeLlmModelDownloader fake;
  late LlmReadinessCubit cubit;

  setUp(() {
    fake = FakeLlmModelDownloader();
    cubit = LlmReadinessCubit(downloader: fake);
  });

  tearDown(() async {
    await cubit.close();
    await fake.dispose();
  });

  group('LlmReadinessCubit', () {
    test('starts in idle', () {
      expect(cubit.state.phase, LlmReadinessPhase.idle);
      expect(cubit.state.progressBytes, 0);
      expect(cubit.state.totalBytes, 0);
      expect(cubit.state.failureReason, isNull);
    });

    test('bootstrap flips idle → ready when file is already on disk', () async {
      fake.alreadyDownloaded = true;
      final emissions = await _drain(
        cubit,
        () => cubit.bootstrap(),
        expectedAtLeast: 1,
      );
      expect(emissions, hasLength(1));
      expect(emissions.single.phase, LlmReadinessPhase.ready);
    });

    test('bootstrap leaves idle when no file present', () async {
      fake.alreadyDownloaded = false;
      final emissions = await _drain(
        cubit,
        () => cubit.bootstrap(),
        expectedAtLeast: 0,
        timeout: const Duration(milliseconds: 50),
      );
      expect(emissions, isEmpty);
      expect(cubit.state.phase, LlmReadinessPhase.idle);
    });

    test('happy path: idle → downloading → verifying → ready', () async {
      final emissions = <LlmReadinessState>[];
      final sub = cubit.stream.listen(emissions.add);

      await cubit.start();
      // start() emits the initial downloading frame synchronously.
      expect(cubit.state.phase, LlmReadinessPhase.downloading);

      fake.emitDownloading(100, 1000);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      fake.emitDownloading(500, 1000);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      fake.emitVerifying();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      fake.emitReady();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();

      final phases = emissions.map((s) => s.phase).toList();
      expect(phases, [
        LlmReadinessPhase.downloading, // initial reset by start()
        LlmReadinessPhase.downloading, // 100/1000 frame
        LlmReadinessPhase.downloading, // 500/1000 frame
        LlmReadinessPhase.verifying,
        LlmReadinessPhase.ready,
      ]);
      expect(emissions[1].progressBytes, 100);
      expect(emissions[1].totalBytes, 1000);
      expect(emissions[2].progressBytes, 500);
      expect(emissions[2].totalBytes, 1000);
      expect(emissions.last.failureReason, isNull);
    });

    test('cancel mid-flight: deletes partial, returns to idle', () async {
      await cubit.start();
      fake.emitDownloading(200, 1000);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(cubit.state.phase, LlmReadinessPhase.downloading);
      expect(fake.deletePartialCount, 0);

      await cubit.cancel();

      expect(cubit.state.phase, LlmReadinessPhase.idle);
      expect(cubit.state.progressBytes, 0);
      expect(fake.deletePartialCount, 1);
    });

    test('hash mismatch surfaces failed phase + reason', () async {
      await cubit.start();
      fake.emitDownloading(1000, 1000);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      fake.emitFailed('Hash mismatch');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(cubit.state.phase, LlmReadinessPhase.failed);
      expect(cubit.state.failureReason, 'Hash mismatch');
    });

    test('stream error surfaces failed phase with humanised reason', () async {
      await cubit.start();
      fake.emitError(const FormatException('Bad gateway'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(cubit.state.phase, LlmReadinessPhase.failed);
      expect(cubit.state.failureReason, 'Bad gateway');
    });

    test('start() while a previous download is in flight cancels the old one', () async {
      await cubit.start();
      fake.emitDownloading(100, 1000);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // Second start. The new subscription should replace the old one;
      // a stale `emitReady()` from the previous fake controller must not
      // flip the cubit into `ready`.
      await cubit.start();
      // The fake's old controller was closed by emitReady→close in
      // happy-path tests; here we just verify a subsequent emit on the
      // *current* (new) controller drives the cubit normally.
      fake.emitDownloading(50, 1000);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(cubit.state.phase, LlmReadinessPhase.downloading);
      expect(cubit.state.progressBytes, 50);
    });

    test('progressFraction clamps to [0, 1] and handles zero total', () {
      const a = LlmReadinessState(
        phase: LlmReadinessPhase.downloading,
        progressBytes: 0,
        totalBytes: 0,
      );
      const b = LlmReadinessState(
        phase: LlmReadinessPhase.downloading,
        progressBytes: 500,
        totalBytes: 1000,
      );
      const c = LlmReadinessState(
        phase: LlmReadinessPhase.downloading,
        progressBytes: 5000,
        totalBytes: 1000, // shouldn't happen in practice; defensive clamp
      );

      expect(a.progressFraction, 0);
      expect(b.progressFraction, 0.5);
      expect(c.progressFraction, 1);
    });
  });
}
