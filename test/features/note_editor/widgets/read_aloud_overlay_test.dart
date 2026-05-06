import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/features/note_editor/widgets/read_aloud_overlay.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/services/speech/tts_models.dart';
import 'package:noti_notes_app/theme/app_theme.dart';
import 'package:noti_notes_app/theme/app_typography.dart';
import 'package:noti_notes_app/theme/tokens/typography_tokens.dart';

class _RecordingNoteEditorBloc extends Bloc<NoteEditorEvent, NoteEditorState> {
  _RecordingNoteEditorBloc(NoteEditorState initial) : super(initial) {
    on<NoteEditorEvent>((event, emit) {
      events.add(event);
    });
  }

  final List<NoteEditorEvent> events = [];

  void push(NoteEditorState state) => emit(state);
}

Note _noteWith(List<String> texts) {
  return Note(
    <String>{},
    null,
    null,
    <Map<String, dynamic>>[],
    null,
    null,
    id: 'n1',
    title: '',
    content: '',
    dateCreated: DateTime(2026, 5, 6),
    colorBackground: const Color(0xFFEDE6D6),
    fontColor: const Color(0xFF1C1B1A),
    hasGradient: false,
    blocks: [
      for (var i = 0; i < texts.length; i++)
        <String, dynamic>{'type': 'text', 'id': 'b$i', 'text': texts[i]},
    ],
  );
}

/// Builds a `NotiText` with empty styles so widget tests don't go through
/// GoogleFonts (which would touch the asset bundle / network). Mirrors the
/// `_stubText` pattern in `permission_explainer_sheet_test.dart`.
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

Future<void> _pumpOverlay(
  WidgetTester tester, {
  required _RecordingNoteEditorBloc bloc,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.bone(text: _stubText()),
      home: BlocProvider<NoteEditorBloc>.value(
        value: bloc,
        child: const Scaffold(body: ReadAloudOverlay()),
      ),
    ),
  );
}

void main() {
  group('ReadAloudOverlay', () {
    testWidgets('renders nothing when isReadingAloud is false', (tester) async {
      final bloc = _RecordingNoteEditorBloc(
        NoteEditorState(note: _noteWith(['hello'])),
      );
      await _pumpOverlay(tester, bloc: bloc);

      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
      expect(find.byIcon(Icons.stop_rounded), findsNothing);
      await bloc.close();
    });

    testWidgets('renders pill with block label and stop button when reading', (tester) async {
      final bloc = _RecordingNoteEditorBloc(
        NoteEditorState(
          note: _noteWith(['first', 'second']),
          isReadingAloud: true,
          currentReadBlockIndex: 0,
        ),
      );
      await _pumpOverlay(tester, bloc: bloc);

      expect(find.text('Reading block 1 of 2'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      await bloc.close();
    });

    testWidgets('paused state swaps pause icon for play_arrow', (tester) async {
      final bloc = _RecordingNoteEditorBloc(
        NoteEditorState(
          note: _noteWith(['only-block']),
          isReadingAloud: true,
          isReadAloudPaused: true,
          currentReadBlockIndex: 0,
        ),
      );
      await _pumpOverlay(tester, bloc: bloc);

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
      await bloc.close();
    });

    testWidgets('tap pause dispatches ReadAloudPaused', (tester) async {
      final bloc = _RecordingNoteEditorBloc(
        NoteEditorState(
          note: _noteWith(['x']),
          isReadingAloud: true,
          currentReadBlockIndex: 0,
        ),
      );
      await _pumpOverlay(tester, bloc: bloc);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pump();
      expect(bloc.events.whereType<ReadAloudPaused>(), hasLength(1));
      await bloc.close();
    });

    testWidgets('tap resume dispatches ReadAloudResumed', (tester) async {
      final bloc = _RecordingNoteEditorBloc(
        NoteEditorState(
          note: _noteWith(['x']),
          isReadingAloud: true,
          isReadAloudPaused: true,
          currentReadBlockIndex: 0,
        ),
      );
      await _pumpOverlay(tester, bloc: bloc);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      expect(bloc.events.whereType<ReadAloudResumed>(), hasLength(1));
      await bloc.close();
    });

    testWidgets('tap stop dispatches ReadAloudStopped', (tester) async {
      final bloc = _RecordingNoteEditorBloc(
        NoteEditorState(
          note: _noteWith(['x']),
          isReadingAloud: true,
          currentReadBlockIndex: 0,
        ),
      );
      await _pumpOverlay(tester, bloc: bloc);

      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pump();
      expect(bloc.events.whereType<ReadAloudStopped>(), hasLength(1));
      await bloc.close();
    });

    testWidgets('progress slices text into before/active/after spans', (tester) async {
      const fullText = 'hello world';
      final bloc = _RecordingNoteEditorBloc(
        NoteEditorState(
          note: _noteWith([fullText]),
          isReadingAloud: true,
          currentReadBlockIndex: 0,
          readProgress: const TtsProgress(
            text: fullText,
            start: 6,
            end: 11,
            word: 'world',
          ),
        ),
      );
      await _pumpOverlay(tester, bloc: bloc);

      // The Text.rich widget assembles "hello " + "world" + "" — find by
      // RichText and inspect its inline span structure.
      final richText = tester.widget<RichText>(find.byType(RichText).first);
      final root = richText.text as TextSpan;
      final children = root.children!.cast<TextSpan>();
      expect(children, hasLength(3));
      expect(children[0].text, 'hello ');
      expect(children[1].text, 'world');
      expect(children[1].style?.fontWeight, FontWeight.w700);
      expect(children[2].text, '');
      await bloc.close();
    });
  });
}
