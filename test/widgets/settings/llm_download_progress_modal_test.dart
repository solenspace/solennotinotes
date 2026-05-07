import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/settings/cubit/llm_readiness_cubit.dart';
import 'package:noti_notes_app/features/settings/widgets/llm_download_progress_modal.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens.dart';

import '../../services/ai/fake_llm_model_downloader.dart';

NotiText _stubText(WritingFont font, Brightness brightness) {
  const blank = TextStyle();
  return NotiText(
    writingFont: font,
    brightness: brightness,
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

ThemeData _theme() => AppTheme.bone(text: _stubText(WritingFont.inter, Brightness.light));

/// Builds a host widget that surfaces the modal on a button tap, with a
/// real [LlmReadinessCubit] backed by a fake downloader so we can drive
/// the modal through every phase.
Widget _harness({required FakeLlmModelDownloader fake}) {
  return MaterialApp(
    theme: _theme(),
    home: BlocProvider<LlmReadinessCubit>(
      create: (_) => LlmReadinessCubit(downloader: fake),
      child: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => LlmDownloadProgressModal.show(context),
                child: const Text('Open modal'),
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// Opens the modal without [WidgetTester.pumpAndSettle] — the verifying
/// phase renders an indeterminate `LinearProgressIndicator(value: null)`
/// whose animation never settles, so the test pumps a fixed handful of
/// frames and proceeds.
Future<void> _openModal(WidgetTester tester) async {
  await tester.tap(find.text('Open modal'));
  await tester.pump(); // start route transition
  await tester.pump(const Duration(milliseconds: 200)); // finish transition
}

LlmReadinessCubit _cubitFor(WidgetTester tester) {
  // Find any element that lives inside the BlocProvider subtree.
  final element = tester.element(find.text('Open modal'));
  return BlocProvider.of<LlmReadinessCubit>(element);
}

void main() {
  late FakeLlmModelDownloader fake;

  setUp(() => fake = FakeLlmModelDownloader());
  tearDown(() => fake.dispose());

  group('LlmDownloadProgressModal', () {
    testWidgets('renders progress bar + byte readout while downloading', (tester) async {
      await tester.pumpWidget(_harness(fake: fake));

      // Drive the cubit into a downloading state BEFORE opening the modal,
      // so the first frame inside the dialog renders that phase.
      final cubit = _cubitFor(tester);
      await cubit.start();
      fake.emitDownloading(250, 1000);
      await tester.pump();

      await _openModal(tester);

      expect(find.text('Downloading AI model'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.textContaining('MB'), findsAtLeastNWidgets(1));
    });

    testWidgets('liveRegion semantics announces percentage', (tester) async {
      await tester.pumpWidget(_harness(fake: fake));
      final cubit = _cubitFor(tester);
      await cubit.start();
      fake.emitDownloading(420, 1000);
      await tester.pump();

      await _openModal(tester);

      final liveRegion = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.liveRegion ?? false) &&
              (w.properties.label ?? '').contains('Downloading AI model'),
        ),
      );
      expect(liveRegion.properties.label, contains('42 percent'));
    });

    testWidgets('verifying phase swaps to indeterminate progress', (tester) async {
      await tester.pumpWidget(_harness(fake: fake));
      final cubit = _cubitFor(tester);
      await cubit.start();
      fake.emitDownloading(1000, 1000);
      await tester.pump();
      fake.emitVerifying();
      await tester.pump();

      await _openModal(tester);

      expect(find.text('Verifying download'), findsOneWidget);
      // Indeterminate `LinearProgressIndicator(value: null)` still renders;
      // we just assert the phase label so we don't depend on internal anim.
    });

    testWidgets('failed phase shows error + Retry button', (tester) async {
      await tester.pumpWidget(_harness(fake: fake));
      final cubit = _cubitFor(tester);
      await cubit.start();
      fake.emitFailed('Hash mismatch');
      await tester.pump();

      await _openModal(tester);

      expect(find.text('Download failed'), findsOneWidget);
      expect(find.text('Hash mismatch'), findsAtLeastNWidgets(1));
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });
  });
}
