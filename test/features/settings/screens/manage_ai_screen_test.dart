import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noti_notes_app/features/settings/cubit/llm_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_state.dart';
import 'package:noti_notes_app/features/settings/screens/manage_ai_screen.dart';
import 'package:noti_notes_app/services/ai/llm_model_constants.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens/typography_tokens.dart';

import '../../../services/ai/fake_llm_model_downloader.dart';

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

Future<LlmReadinessCubit> _pump(
  WidgetTester tester, {
  required FakeLlmModelDownloader fake,
}) async {
  final cubit = LlmReadinessCubit(downloader: fake)
    ..emit(const LlmReadinessState(phase: LlmReadinessPhase.ready));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.bone(text: _stubText()),
      home: BlocProvider<LlmReadinessCubit>.value(
        value: cubit,
        child: const ManageAiScreen(),
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

void main() {
  late FakeLlmModelDownloader fake;

  setUp(() => fake = FakeLlmModelDownloader());
  tearDown(() => fake.dispose());

  group('ManageAiScreen', () {
    testWidgets('renders model identity from constants', (tester) async {
      final cubit = await _pump(tester, fake: fake);

      expect(find.text(LlmModelConstants.filename), findsOneWidget);
      expect(find.text(LlmModelConstants.version), findsOneWidget);
      expect(find.text('On this device, verified'), findsOneWidget);

      addTearDown(cubit.close);
    });

    testWidgets('Re-download → confirm → calls disable + start', (tester) async {
      final cubit = await _pump(tester, fake: fake);

      await tester.tap(find.text('Re-download model'));
      await tester.pumpAndSettle();
      expect(find.text('Re-download model?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Re-download'));
      // The cubit's disable + start fire async; pump enough frames for them.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fake.deleteAllCount, greaterThanOrEqualTo(1));
      // start() opens the download stream.
      expect(cubit.state.phase, LlmReadinessPhase.downloading);

      addTearDown(cubit.close);
    });

    testWidgets('Re-download → cancel dialog → no side-effects', (tester) async {
      final cubit = await _pump(tester, fake: fake);

      await tester.tap(find.text('Re-download model'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(fake.deleteAllCount, 0);
      expect(cubit.state.phase, LlmReadinessPhase.ready);

      addTearDown(cubit.close);
    });

    testWidgets('Delete → confirm → calls disable, returns to idle', (tester) async {
      final cubit = await _pump(tester, fake: fake);

      await tester.tap(find.text('Delete model and disable AI'));
      await tester.pumpAndSettle();
      expect(find.text('Delete model?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fake.deleteAllCount, 1);
      expect(cubit.state.phase, LlmReadinessPhase.idle);

      addTearDown(cubit.close);
    });
  });
}
