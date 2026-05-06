import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/features/note_editor/widgets/read_aloud_button.dart';

/// Stand-in bloc that records every event without running the real
/// handlers. Mirrors the shape of `_RecordingNoteEditorBloc` in
/// `dictation_button_test.dart`.
class _RecordingNoteEditorBloc extends Bloc<NoteEditorEvent, NoteEditorState> {
  _RecordingNoteEditorBloc({bool initiallyReading = false})
      : super(NoteEditorState(isReadingAloud: initiallyReading)) {
    on<NoteEditorEvent>((event, emit) {
      events.add(event);
    });
  }

  final List<NoteEditorEvent> events = [];
}

Future<void> _pumpButton(
  WidgetTester tester, {
  required _RecordingNoteEditorBloc bloc,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<NoteEditorBloc>.value(
        value: bloc,
        child: const Scaffold(body: Center(child: ReadAloudButton())),
      ),
    ),
  );
}

void main() {
  group('ReadAloudButton', () {
    testWidgets('idle state shows volume_up icon', (tester) async {
      final bloc = _RecordingNoteEditorBloc();
      await _pumpButton(tester, bloc: bloc);

      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsNothing);
      await bloc.close();
    });

    testWidgets('reading state shows stop icon', (tester) async {
      final bloc = _RecordingNoteEditorBloc(initiallyReading: true);
      await _pumpButton(tester, bloc: bloc);

      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
      await bloc.close();
    });

    testWidgets('tap when idle dispatches ReadAloudRequested with null index', (tester) async {
      final bloc = _RecordingNoteEditorBloc();
      await _pumpButton(tester, bloc: bloc);

      await tester.tap(find.byIcon(Icons.volume_up_rounded));
      await tester.pump();

      final requests = bloc.events.whereType<ReadAloudRequested>().toList();
      expect(requests, hasLength(1));
      expect(requests.single.blockIndex, isNull);
      expect(bloc.events.whereType<ReadAloudStopped>(), isEmpty);
      await bloc.close();
    });

    testWidgets('tap while reading dispatches ReadAloudStopped', (tester) async {
      final bloc = _RecordingNoteEditorBloc(initiallyReading: true);
      await _pumpButton(tester, bloc: bloc);

      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pump();

      expect(bloc.events.whereType<ReadAloudStopped>(), hasLength(1));
      expect(bloc.events.whereType<ReadAloudRequested>(), isEmpty);
      await bloc.close();
    });
  });
}
