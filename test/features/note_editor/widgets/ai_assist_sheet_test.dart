import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/features/note_editor/cubit/ai_assist_cubit.dart';
import 'package:noti_notes_app/features/note_editor/cubit/ai_assist_state.dart';
import 'package:noti_notes_app/features/note_editor/widgets/ai_assist_sheet.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/services/ai/ai_action.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens/typography_tokens.dart';

import '../../../services/ai/fake_llm_runtime.dart';
import '../bloc/recording_note_editor_bloc.dart';

NotiText _stubText() {
  const blank = TextStyle();
  return NotiText(
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

Note _noteWith({String title = '', List<String> texts = const []}) {
  return Note(
    <String>{},
    null,
    null,
    <Map<String, dynamic>>[],
    null,
    null,
    id: 'n1',
    title: title,
    content: '',
    dateCreated: DateTime(2026, 5, 7),
    colorBackground: const Color(0xFFEDE6D6),
    fontColor: const Color(0xFF1C1B1A),
    hasGradient: false,
    blocks: [
      for (var i = 0; i < texts.length; i++)
        <String, dynamic>{'type': 'text', 'id': 'b$i', 'text': texts[i]},
    ],
  );
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required RecordingNoteEditorBloc editorBloc,
  required AiAssistCubit aiCubit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.bone(text: _stubText()),
      home: MultiBlocProvider(
        providers: [
          BlocProvider<NoteEditorBloc>.value(value: editorBloc),
          BlocProvider<AiAssistCubit>.value(value: aiCubit),
        ],
        child: const Scaffold(
          body: SizedBox(
            height: 800,
            child: AiAssistSheet(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

AiAssistCubit _cubitFor(FakeLlmRuntime runtime) {
  return AiAssistCubit(
    runtime: runtime,
    modelPathResolver: () async => '/tmp/fake.gguf',
  );
}

void main() {
  late FakeLlmRuntime runtime;
  late AiAssistCubit aiCubit;
  late RecordingNoteEditorBloc editorBloc;

  setUp(() {
    runtime = FakeLlmRuntime();
    aiCubit = _cubitFor(runtime);
    editorBloc = RecordingNoteEditorBloc(
      initial: NoteEditorState(note: _noteWith(texts: ['Carla called Tue.'])),
    );
  });

  tearDown(() async {
    await aiCubit.close();
    await runtime.dispose();
    await editorBloc.close();
  });

  group('AiAssistSheet picker mode', () {
    testWidgets('renders all three action tiles with privacy banner', (tester) async {
      await _pumpSheet(tester, editorBloc: editorBloc, aiCubit: aiCubit);

      expect(find.text('Running on this device — nothing leaves it.'), findsOneWidget);
      for (final action in AiAction.values) {
        expect(find.text(action.label), findsOneWidget);
      }
    });

    testWidgets('tap on Summarize starts generation', (tester) async {
      runtime.scriptedTokens = ['Carla'];
      await _pumpSheet(tester, editorBloc: editorBloc, aiCubit: aiCubit);

      await tester.tap(find.text(AiAction.summarize.label));
      await tester.pump(); // emits the start state
      await tester.pump(const Duration(milliseconds: 100));

      expect(runtime.generateCalls, 1);
      expect(runtime.lastPrompt, contains('Carla called Tue.'));
    });
  });

  group('AiAssistSheet result mode (summarize / rewrite)', () {
    testWidgets('Replace dispatches BlocksReplaced collapsing text blocks', (tester) async {
      // Seed cubit into result mode directly so we control the draft text.
      runtime.scriptedTokens = ['Carla called.'];
      await _pumpSheet(tester, editorBloc: editorBloc, aiCubit: aiCubit);
      await tester.tap(find.text(AiAction.summarize.label));
      // Drain the scripted tokens so the cubit transitions to finished.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(aiCubit.state.finished, isTrue);
      expect(aiCubit.state.draftOutput, 'Carla called.');

      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
      await tester.pump();

      final replaces = editorBloc.events.whereType<BlocksReplaced>().toList();
      expect(replaces, hasLength(1));
      // The result is exactly one text block carrying the AI output.
      expect(replaces.single.blocks, hasLength(1));
      expect(replaces.single.blocks.single['type'], 'text');
      expect(replaces.single.blocks.single['text'], 'Carla called.');
    });

    testWidgets('Append dispatches BlocksReplaced with original blocks intact', (tester) async {
      runtime.scriptedTokens = ['Extra context.'];
      await _pumpSheet(tester, editorBloc: editorBloc, aiCubit: aiCubit);
      await tester.tap(find.text(AiAction.rewrite.label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Append'));
      await tester.pump();

      final replaces = editorBloc.events.whereType<BlocksReplaced>().toList();
      expect(replaces, hasLength(1));
      expect(replaces.single.blocks, hasLength(2));
      expect(replaces.single.blocks.first['text'], 'Carla called Tue.');
      expect(replaces.single.blocks.last['type'], 'text');
      expect(replaces.single.blocks.last['text'], 'Extra context.');
    });

    testWidgets('Discard pops the sheet without dispatching events', (tester) async {
      runtime.scriptedTokens = ['done'];
      await _pumpSheet(tester, editorBloc: editorBloc, aiCubit: aiCubit);
      await tester.tap(find.text(AiAction.summarize.label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Discard tap should leave editorBloc.events untouched (no BlocksReplaced).
      await tester.tap(find.widgetWithText(OutlinedButton, 'Discard'));
      await tester.pump();

      expect(editorBloc.events.whereType<BlocksReplaced>(), isEmpty);
      expect(editorBloc.events.whereType<TitleChanged>(), isEmpty);
    });
  });

  group('AiAssistSheet result mode (suggestTitle)', () {
    testWidgets('Use this title dispatches TitleChanged with selected line', (tester) async {
      runtime.scriptedTokens = ['1. Alpha\n', '2. Beta\n', '3. Gamma'];
      await _pumpSheet(tester, editorBloc: editorBloc, aiCubit: aiCubit);
      await tester.tap(find.text(AiAction.suggestTitle.label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The first option (Alpha) is selected by default.
      await tester.tap(find.widgetWithText(FilledButton, 'Use this title'));
      await tester.pump();

      final titles = editorBloc.events.whereType<TitleChanged>().toList();
      expect(titles, hasLength(1));
      expect(titles.single.title, 'Alpha');
    });
  });

  group('AiAssistSheet streaming mode', () {
    testWidgets('Stop button is visible while generating', (tester) async {
      // Drive the cubit into a synthetic streaming state via the test
      // seam — that avoids the fake-async timer/subscription plumbing
      // the production `start` path runs (cubit lifecycle is exercised
      // separately by `ai_assist_cubit_test.dart`).
      aiCubit.debugEmit(
        const AiAssistState(
          activeAction: AiAction.summarize,
          isGenerating: true,
          firstTokenArrived: true,
          draftOutput: 'Partial',
        ),
      );

      await _pumpSheet(tester, editorBloc: editorBloc, aiCubit: aiCubit);
      await tester.pump();

      expect(find.widgetWithText(OutlinedButton, 'Stop'), findsOneWidget);

      // Reset before tearDown so the cubit isn't holding a synthetic
      // streaming state when its widgets are disposed.
      aiCubit.debugEmit(const AiAssistState.initial());
      await tester.pump();
    });
  });
}
