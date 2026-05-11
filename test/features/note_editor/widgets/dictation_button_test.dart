import 'package:flutter/material.dart';
import 'package:noti_notes_app/generated/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/features/note_editor/widgets/dictation_button.dart';
import 'package:noti_notes_app/services/speech/stt_service.dart';

import '../../../services/speech/fake_stt_service.dart';
import '../bloc/recording_note_editor_bloc.dart';

Future<void> _pumpButton(
  WidgetTester tester, {
  required RecordingNoteEditorBloc bloc,
  required FakeSttService stt,
  bool accessibleNavigation = false,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(accessibleNavigation: accessibleNavigation),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepositoryProvider<SttService>.value(
          value: stt,
          child: BlocProvider<NoteEditorBloc>.value(
            value: bloc,
            child: const Scaffold(body: Center(child: DictationButton())),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('DictationButton', () {
    testWidgets('renders nothing when STT is offline-incapable', (tester) async {
      final bloc = RecordingNoteEditorBloc();
      final stt = FakeSttService(offlineCapable: false);
      await _pumpButton(tester, bloc: bloc, stt: stt);

      expect(find.byIcon(Icons.record_voice_over_rounded), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
      addTearDown(bloc.close);
    });

    testWidgets('long-press dispatches DictationStarted', (tester) async {
      final bloc = RecordingNoteEditorBloc();
      final stt = FakeSttService();
      await _pumpButton(tester, bloc: bloc, stt: stt);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.record_voice_over_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();

      expect(bloc.events.whereType<DictationStarted>(), hasLength(1));
      // Release without sliding fires DictationStopped.
      expect(bloc.events.whereType<DictationStopped>(), hasLength(1));
      addTearDown(bloc.close);
    });

    testWidgets('slide past the cancel threshold dispatches DictationCancelled', (tester) async {
      final bloc = RecordingNoteEditorBloc();
      final stt = FakeSttService();
      await _pumpButton(tester, bloc: bloc, stt: stt);

      final start = tester.getCenter(find.byIcon(Icons.record_voice_over_rounded));
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      // Slide far enough past the 80-px cancel distance.
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(bloc.events.whereType<DictationStarted>(), hasLength(1));
      expect(bloc.events.whereType<DictationCancelled>(), hasLength(1));
      // Slide-cancel suppresses the stop event.
      expect(bloc.events.whereType<DictationStopped>(), isEmpty);
      addTearDown(bloc.close);
    });

    testWidgets('tap-to-toggle when accessibleNavigation is on', (tester) async {
      final bloc = RecordingNoteEditorBloc();
      final stt = FakeSttService();
      await _pumpButton(tester, bloc: bloc, stt: stt, accessibleNavigation: true);

      // First tap → DictationStarted.
      await tester.tap(find.byIcon(Icons.record_voice_over_rounded));
      await tester.pump();
      expect(bloc.events.whereType<DictationStarted>(), hasLength(1));
      expect(bloc.events.whereType<DictationStopped>(), isEmpty);

      addTearDown(bloc.close);
    });

    testWidgets('renders stop glyph while isDictating is true', (tester) async {
      final bloc = RecordingNoteEditorBloc(
        initial: const NoteEditorState(isDictating: true),
      );
      final stt = FakeSttService();
      await _pumpButton(tester, bloc: bloc, stt: stt);

      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(find.byIcon(Icons.record_voice_over_rounded), findsNothing);
      addTearDown(bloc.close);
    });
  });
}
