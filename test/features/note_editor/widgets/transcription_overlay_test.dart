import 'package:flutter/material.dart';
import 'package:noti_notes_app/generated/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/note_editor/cubit/transcription_cubit.dart';
import 'package:noti_notes_app/features/note_editor/widgets/transcription_overlay.dart';
import 'package:noti_notes_app/services/ai/whisper_runtime.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens/typography_tokens.dart';

import '../../../services/ai/fake_whisper_runtime.dart';

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

/// Builds an app-shell widget with a button that opens
/// [TranscriptionOverlay.show] over a [FakeWhisperRuntime]. The button
/// stores the [TranscriptionAcceptanceResult] in [resultCell] so tests
/// can assert on the user's chosen accept path.
Widget _harness({
  required FakeWhisperRuntime fake,
  required ValueNotifier<TranscriptionAcceptanceResult?> resultCell,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: AppTheme.bone(text: _stubText()),
    home: Builder(
      builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await TranscriptionOverlay.show(
                  context,
                  audioFilePath: '/audio.m4a',
                  cubitFactory: () => TranscriptionCubit(
                    runtime: fake,
                    modelPathResolver: () async => '/model.bin',
                  ),
                );
                resultCell.value = r;
              },
              child: const Text('Open overlay'),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _openOverlay(WidgetTester tester) async {
  // The default 800x600 surface clips the bottom sheet's ready-mode
  // accept-button stack; widgets render past the viewport bottom and
  // tap()s miss. Bump the surface so positions stay within the render
  // tree.
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.tap(find.text('Open overlay'));
  // The modal bottom sheet animates in over ~250ms; settle the animation
  // and any synchronous initial cubit emit before tests assert.
  await tester.pumpAndSettle();
}

void main() {
  late FakeWhisperRuntime fake;
  late ValueNotifier<TranscriptionAcceptanceResult?> result;

  setUp(() {
    fake = FakeWhisperRuntime();
    result = ValueNotifier<TranscriptionAcceptanceResult?>(null);
  });

  tearDown(() async {
    await fake.dispose();
    result.dispose();
  });

  group('TranscriptionOverlay', () {
    testWidgets('running mode renders progress bar + Cancel button', (tester) async {
      // Don't auto-script; we want the cubit stuck in running so the
      // overlay opens in that mode.
      await tester.pumpWidget(_harness(fake: fake, resultCell: result));
      await _openOverlay(tester);

      // The first frame inside the overlay shows the running body
      // because the cubit emits running synchronously from start().
      expect(find.text('Transcribing audio'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('Cancel mid-progress dismisses with discard', (tester) async {
      await tester.pumpWidget(_harness(fake: fake, resultCell: result));
      await _openOverlay(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(result.value?.kind, TranscriptionAcceptance.discard);
      expect(fake.activeStreamCancelled, isTrue);
    });

    testWidgets('ready mode renders transcript + three accept buttons', (tester) async {
      fake.scriptedEvents = const [
        TranscriptionProgress(0.5),
        TranscriptionResult('hello world'),
      ];
      await tester.pumpWidget(_harness(fake: fake, resultCell: result));
      await _openOverlay(tester);

      // Allow scripted events to flow through to the cubit.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Transcript ready'), findsOneWidget);
      expect(find.text('hello world'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Insert below'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Replace audio'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Discard'), findsOneWidget);
    });

    testWidgets('Insert below pops with insertBelow + transcript', (tester) async {
      fake.scriptedEvents = const [TranscriptionResult('the transcript')];
      await tester.pumpWidget(_harness(fake: fake, resultCell: result));
      await _openOverlay(tester);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.widgetWithText(FilledButton, 'Insert below'));
      await tester.pumpAndSettle();

      expect(result.value?.kind, TranscriptionAcceptance.insertBelow);
      expect(result.value?.transcript, 'the transcript');
    });

    testWidgets('Replace audio pops with replaceAudio + transcript', (tester) async {
      fake.scriptedEvents = const [TranscriptionResult('replace me')];
      await tester.pumpWidget(_harness(fake: fake, resultCell: result));
      await _openOverlay(tester);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Replace audio'));
      await tester.pumpAndSettle();

      expect(result.value?.kind, TranscriptionAcceptance.replaceAudio);
      expect(result.value?.transcript, 'replace me');
    });

    testWidgets('Discard from ready pops with discard', (tester) async {
      fake.scriptedEvents = const [TranscriptionResult('whatever')];
      await tester.pumpWidget(_harness(fake: fake, resultCell: result));
      await _openOverlay(tester);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(result.value?.kind, TranscriptionAcceptance.discard);
    });

    testWidgets('failed mode renders error + Try again + Discard', (tester) async {
      fake.loadThrows = StateError('cannot load model');
      await tester.pumpWidget(_harness(fake: fake, resultCell: result));
      await _openOverlay(tester);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Transcription failed'), findsOneWidget);
      expect(find.textContaining('cannot load model'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Discard'), findsOneWidget);
    });
  });
}
