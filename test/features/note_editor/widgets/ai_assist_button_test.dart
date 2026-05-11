import 'package:flutter/material.dart';
import 'package:noti_notes_app/generated/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noti_notes_app/features/note_editor/widgets/ai_assist_button.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_state.dart';
import 'package:noti_notes_app/services/device/ai_tier.dart';
import 'package:noti_notes_app/services/device/device_capability_service.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens/typography_tokens.dart';

import '../../../services/ai/fake_model_downloader.dart';
import '../../../services/device/fake_device_capability_service.dart';

/// Builds a `NotiText` with empty styles so widget tests don't go through
/// GoogleFonts (which would touch the asset bundle).
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

/// Pumps an [AiAssistButton] inside an editor-style provider tree with
/// [tier] and [phase] forced to the values under test.
Future<LlmReadinessCubit> _pumpButton(
  WidgetTester tester, {
  required AiTier tier,
  required LlmReadinessPhase phase,
}) async {
  final capability = FakeDeviceCapabilityService()..aiTier = tier;
  final downloader = FakeModelDownloader();
  final cubit = LlmReadinessCubit(downloader: downloader);
  if (phase == LlmReadinessPhase.ready) {
    cubit.emit(const LlmReadinessState(phase: LlmReadinessPhase.ready));
  } else if (phase != LlmReadinessPhase.idle) {
    cubit.emit(LlmReadinessState(phase: phase));
  }

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.bone(text: _stubText()),
      home: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<DeviceCapabilityService>.value(value: capability),
        ],
        child: BlocProvider<LlmReadinessCubit>.value(
          value: cubit,
          child: const Scaffold(body: Center(child: AiAssistButton())),
        ),
      ),
    ),
  );
  return cubit;
}

void main() {
  const tooltipMessage = 'AI assist — long-press to manage';

  group('AiAssistButton gating', () {
    testWidgets('hidden when AI tier is unsupported even if model is ready', (tester) async {
      final cubit = await _pumpButton(
        tester,
        tier: AiTier.unsupported,
        phase: LlmReadinessPhase.ready,
      );

      expect(find.byTooltip(tooltipMessage), findsNothing);
      expect(find.text('✦'), findsNothing);

      addTearDown(cubit.close);
    });

    testWidgets('hidden when model is not ready even on a capable device', (tester) async {
      final cubit = await _pumpButton(
        tester,
        tier: AiTier.full,
        phase: LlmReadinessPhase.idle,
      );

      expect(find.byTooltip(tooltipMessage), findsNothing);
      addTearDown(cubit.close);
    });

    testWidgets('hidden while download is in flight', (tester) async {
      final cubit = await _pumpButton(
        tester,
        tier: AiTier.full,
        phase: LlmReadinessPhase.downloading,
      );

      expect(find.byTooltip(tooltipMessage), findsNothing);
      addTearDown(cubit.close);
    });

    testWidgets('renders ✦ glyph when both gates pass', (tester) async {
      final cubit = await _pumpButton(
        tester,
        tier: AiTier.full,
        phase: LlmReadinessPhase.ready,
      );

      expect(find.byTooltip(tooltipMessage), findsOneWidget);
      expect(find.text('✦'), findsOneWidget);

      addTearDown(cubit.close);
    });

    testWidgets('compact tier still satisfies canRunLlm', (tester) async {
      final cubit = await _pumpButton(
        tester,
        tier: AiTier.compact,
        phase: LlmReadinessPhase.ready,
      );

      expect(find.byTooltip(tooltipMessage), findsOneWidget);
      addTearDown(cubit.close);
    });
  });
}
