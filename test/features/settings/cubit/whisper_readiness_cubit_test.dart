import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/settings/cubit/whisper_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/whisper_readiness_state.dart';
import 'package:noti_notes_app/services/ai/whisper_model_constants.dart';
import 'package:noti_notes_app/services/device/ai_tier.dart';

import '../../../services/ai/fake_model_downloader.dart';

/// Drains [expectedAtLeast] emissions from [cubit] while [act] runs,
/// with a short polling timeout. Mirrors the helper in
/// `llm_readiness_cubit_test.dart`.
Future<List<WhisperReadinessState>> _drain(
  WhisperReadinessCubit cubit,
  Future<void> Function() act, {
  required int expectedAtLeast,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final emissions = <WhisperReadinessState>[];
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
  late FakeModelDownloader fake;
  late WhisperReadinessCubit cubit;

  setUp(() {
    fake = FakeModelDownloader();
    cubit = WhisperReadinessCubit(downloader: fake, tier: AiTier.full);
  });

  tearDown(() async {
    await cubit.close();
    await fake.dispose();
  });

  group('WhisperReadinessCubit', () {
    test('starts in idle', () {
      expect(cubit.state.phase, WhisperReadinessPhase.idle);
      expect(cubit.state.progressBytes, 0);
      expect(cubit.state.totalBytes, 0);
      expect(cubit.state.failureReason, isNull);
    });

    test('exposes the spec resolved from the constructor tier', () {
      // AiTier.full → baseEn (architecture decision #7).
      expect(cubit.spec, WhisperModelConstants.baseEn);
    });

    test('compact tier resolves to whisper-tiny.en', () async {
      final compactCubit = WhisperReadinessCubit(
        downloader: fake,
        tier: AiTier.compact,
      );
      expect(compactCubit.spec, WhisperModelConstants.tinyEn);
      await compactCubit.close();
    });

    test('unsupported tier construction throws StateError', () {
      expect(
        () => WhisperReadinessCubit(
          downloader: fake,
          tier: AiTier.unsupported,
        ),
        throwsStateError,
      );
    });

    test('bootstrap flips idle → ready when file is already on disk', () async {
      fake.alreadyDownloaded = true;
      final emissions = await _drain(
        cubit,
        () => cubit.bootstrap(),
        expectedAtLeast: 1,
      );
      expect(emissions, hasLength(1));
      expect(emissions.single.phase, WhisperReadinessPhase.ready);
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
      expect(cubit.state.phase, WhisperReadinessPhase.idle);
    });

    test('happy path: idle → downloading → verifying → ready', () async {
      final emissions = <WhisperReadinessState>[];
      final sub = cubit.stream.listen(emissions.add);

      await cubit.start();
      expect(cubit.state.phase, WhisperReadinessPhase.downloading);

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
        WhisperReadinessPhase.downloading, // initial reset by start()
        WhisperReadinessPhase.downloading, // 100/1000 frame
        WhisperReadinessPhase.downloading, // 500/1000 frame
        WhisperReadinessPhase.verifying,
        WhisperReadinessPhase.ready,
      ]);
      expect(emissions[1].progressBytes, 100);
      expect(emissions[1].totalBytes, 1000);
      expect(emissions[2].progressBytes, 500);
      expect(emissions.last.failureReason, isNull);
    });

    test('cancel mid-flight: deletes partial under whisper subdir', () async {
      await cubit.start();
      fake.emitDownloading(200, 1000);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await cubit.cancel();

      expect(cubit.state.phase, WhisperReadinessPhase.idle);
      expect(cubit.state.progressBytes, 0);
      expect(fake.deletePartialCountBySubdir['whisper'], 1);
      // LLM partial untouched.
      expect(fake.deletePartialCountBySubdir['llm'], isNull);
    });

    test('disable: deletes file under whisper subdir, returns to idle', () async {
      cubit.emit(const WhisperReadinessState(phase: WhisperReadinessPhase.ready));
      await cubit.disable();

      expect(cubit.state.phase, WhisperReadinessPhase.idle);
      expect(fake.deleteAllCountBySubdir['whisper'], 1);
      expect(fake.deleteAllCountBySubdir['llm'], isNull);
    });

    test('hash mismatch surfaces failed phase + reason', () async {
      await cubit.start();
      fake.emitDownloading(1000, 1000);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      fake.emitFailed('Hash mismatch');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(cubit.state.phase, WhisperReadinessPhase.failed);
      expect(cubit.state.failureReason, 'Hash mismatch');
    });

    test('stream error surfaces failed phase with humanised reason', () async {
      await cubit.start();
      fake.emitError(const FormatException('Bad gateway'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(cubit.state.phase, WhisperReadinessPhase.failed);
      expect(cubit.state.failureReason, 'Bad gateway');
    });

    test('start() while a previous download is in flight cancels old', () async {
      await cubit.start();
      fake.emitDownloading(100, 1000);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await cubit.start();
      fake.emitDownloading(50, 1000);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(cubit.state.phase, WhisperReadinessPhase.downloading);
      expect(cubit.state.progressBytes, 50);
    });
  });
}
