import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noti_notes_app/features/settings/cubit/llm_readiness_cubit.dart';
import 'package:noti_notes_app/generated/app_localizations.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_state.dart';
import 'package:noti_notes_app/features/settings/cubit/whisper_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/whisper_readiness_state.dart';
import 'package:noti_notes_app/features/settings/screens/manage_ai_screen.dart';
import 'package:noti_notes_app/services/ai/llm_model_constants.dart';
import 'package:noti_notes_app/services/ai/whisper_model_constants.dart';
import 'package:noti_notes_app/services/device/ai_tier.dart';
import 'package:noti_notes_app/services/device/device_capability_service.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens/typography_tokens.dart';

import '../../../services/ai/fake_model_downloader.dart';
import '../../../services/device/fake_device_capability_service.dart';

NotiText _stubText() {
  const blank = TextStyle();
  return const NotiText(
    writingFont: WritingFont.inter,
    brightness: Brightness.light,
    displayLg: blank,
    displayMd: blank,
    displaySm: blank,
    headlineMd: blank,
    titleLg: blank,
    titleMd: blank,
    titleSm: blank,
    bodyLg: blank,
    bodyMd: blank,
    bodySm: blank,
    labelLg: blank,
    labelMd: blank,
    labelSm: blank,
  );
}

/// Shared harness — provides every dep the post-Spec-21 ManageAi screen
/// reads: `DeviceCapabilityService` (set to `AiTier.compact` so both
/// `canRunLlm` and `canRunWhisper` are true; the screen renders both
/// sections), the LLM readiness cubit (forced to `ready` so the LLM
/// section's "On this device, verified" copy renders), and the
/// Whisper readiness cubit (forced to `idle` so its presence does not
/// fight LLM-focused assertions).
Future<({LlmReadinessCubit llm, WhisperReadinessCubit whisper})> _pump(
  WidgetTester tester, {
  required FakeModelDownloader fake,
  AiTier tier = AiTier.compact,
  LlmReadinessPhase llmPhase = LlmReadinessPhase.ready,
  WhisperReadinessPhase whisperPhase = WhisperReadinessPhase.idle,
}) async {
  final llmCubit = LlmReadinessCubit(downloader: fake)..emit(LlmReadinessState(phase: llmPhase));
  final whisperCubit = WhisperReadinessCubit(downloader: fake, tier: tier)
    ..emit(WhisperReadinessState(phase: whisperPhase));
  final capability = FakeDeviceCapabilityService()..aiTier = tier;

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.bone(text: _stubText()),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<DeviceCapabilityService>.value(value: capability),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<LlmReadinessCubit>.value(value: llmCubit),
            BlocProvider<WhisperReadinessCubit>.value(value: whisperCubit),
          ],
          child: const ManageAiScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  return (llm: llmCubit, whisper: whisperCubit);
}

void main() {
  late FakeModelDownloader fake;

  setUp(() => fake = FakeModelDownloader());
  tearDown(() => fake.dispose());

  group('ManageAiScreen — LLM section', () {
    testWidgets('renders LLM model identity from constants', (tester) async {
      final cubits = await _pump(tester, fake: fake);

      expect(find.text(LlmModelConstants.filename), findsOneWidget);
      // LLM and Whisper cards both render a Schema row with their own
      // version constant; both happen to be '0.1.0' today, so assert
      // "at least one" rather than coupling to that coincidence.
      expect(find.text(LlmModelConstants.version), findsAtLeastNWidgets(1));
      // 'On this device, verified' renders once for LLM (ready) and
      // never for Whisper (idle by default in this test).
      expect(find.text('On this device, verified'), findsOneWidget);

      addTearDown(cubits.llm.close);
      addTearDown(cubits.whisper.close);
    });

    testWidgets('Re-download (LLM) → confirm → calls disable + start', (tester) async {
      final cubits = await _pump(tester, fake: fake);

      // The LLM tile is "Re-download model"; the Whisper tile is
      // "Re-download transcription model" — disambiguated.
      await tester.tap(find.text('Re-download model'));
      await tester.pumpAndSettle();
      expect(find.text('Re-download model?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Re-download model'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // LLM `disable()` deletes under subdir 'llm'.
      expect(
        fake.deleteAllCountBySubdir['llm'],
        greaterThanOrEqualTo(1),
      );
      expect(cubits.llm.state.phase, LlmReadinessPhase.downloading);

      addTearDown(cubits.llm.close);
      addTearDown(cubits.whisper.close);
    });

    testWidgets('Re-download (LLM) → cancel dialog → no side-effects', (tester) async {
      final cubits = await _pump(tester, fake: fake);

      await tester.tap(find.text('Re-download model'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel', skipOffstage: false));
      await tester.pumpAndSettle();

      expect(fake.deleteAllCountBySubdir['llm'], isNull);
      expect(cubits.llm.state.phase, LlmReadinessPhase.ready);

      addTearDown(cubits.llm.close);
      addTearDown(cubits.whisper.close);
    });

    testWidgets('Delete (LLM) → confirm → calls disable, returns to idle', (tester) async {
      final cubits = await _pump(tester, fake: fake);

      await tester.tap(find.text('Delete model and disable AI'));
      await tester.pumpAndSettle();
      expect(find.text('Delete model?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Delete model and disable AI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fake.deleteAllCountBySubdir['llm'], 1);
      expect(cubits.llm.state.phase, LlmReadinessPhase.idle);

      addTearDown(cubits.llm.close);
      addTearDown(cubits.whisper.close);
    });
  });

  group('ManageAiScreen — Whisper section', () {
    testWidgets('renders Whisper model identity for AiTier.compact', (tester) async {
      // tier=compact ⇒ tinyEn variant
      final cubits = await _pump(
        tester,
        fake: fake,
        tier: AiTier.compact,
        whisperPhase: WhisperReadinessPhase.ready,
      );

      expect(find.text(WhisperModelConstants.tinyEn.filename), findsOneWidget);
      // 'On this device, verified' is now present twice (LLM + Whisper
      // both ready); use widgetWithText predicate to focus on the
      // Whisper card if needed. For now assert findsNWidgets(2).
      expect(find.text('On this device, verified'), findsNWidgets(2));

      addTearDown(cubits.llm.close);
      addTearDown(cubits.whisper.close);
    });

    testWidgets('Whisper Re-download → confirm → calls disable + start', (tester) async {
      final cubits = await _pump(
        tester,
        fake: fake,
        whisperPhase: WhisperReadinessPhase.ready,
      );

      // The Whisper section sits below the LLM section in the ListView;
      // scroll it into view before tapping.
      await tester.scrollUntilVisible(
        find.text('Re-download transcription model'),
        300,
      );
      await tester.tap(find.text('Re-download transcription model'));
      await tester.pumpAndSettle();
      expect(find.text('Re-download transcription model?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Re-download transcription model'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        fake.deleteAllCountBySubdir['whisper'],
        greaterThanOrEqualTo(1),
      );
      // LLM untouched.
      expect(fake.deleteAllCountBySubdir['llm'], isNull);
      expect(cubits.whisper.state.phase, WhisperReadinessPhase.downloading);

      addTearDown(cubits.llm.close);
      addTearDown(cubits.whisper.close);
    });

    testWidgets('Whisper Delete → confirm → returns to idle', (tester) async {
      final cubits = await _pump(
        tester,
        fake: fake,
        whisperPhase: WhisperReadinessPhase.ready,
      );

      await tester.scrollUntilVisible(
        find.text('Delete model and disable transcription'),
        300,
      );
      await tester.tap(find.text('Delete model and disable transcription'));
      await tester.pumpAndSettle();
      expect(find.text('Delete transcription model?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Delete model and disable transcription'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fake.deleteAllCountBySubdir['whisper'], 1);
      expect(cubits.whisper.state.phase, WhisperReadinessPhase.idle);

      addTearDown(cubits.llm.close);
      addTearDown(cubits.whisper.close);
    });
  });

  group('ManageAiScreen — gating', () {
    testWidgets('hides both sections when tier is unsupported', (tester) async {
      // Build a hand-rolled harness because `_pump` constructs a
      // WhisperReadinessCubit, which throws on `AiTier.unsupported`.
      final llmCubit = LlmReadinessCubit(downloader: fake)
        ..emit(const LlmReadinessState(phase: LlmReadinessPhase.ready));
      final capability = FakeDeviceCapabilityService()..aiTier = AiTier.unsupported;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.bone(text: _stubText()),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<DeviceCapabilityService>.value(value: capability),
            ],
            child: BlocProvider<LlmReadinessCubit>.value(
              value: llmCubit,
              child: const ManageAiScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(LlmModelConstants.filename), findsNothing);
      expect(find.text('Re-download model'), findsNothing);
      expect(find.text('Re-download transcription model'), findsNothing);

      addTearDown(llmCubit.close);
    });
  });
}
