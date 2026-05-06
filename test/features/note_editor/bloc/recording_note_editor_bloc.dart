import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';

import '../../../repositories/audio/fake_audio_repository.dart';
import '../../../repositories/noti_identity/fake_noti_identity_repository.dart';
import '../../../repositories/notes/fake_notes_repository.dart';
import '../../../services/permissions/fake_permissions_service.dart';
import '../../../services/speech/fake_stt_service.dart';
import '../../../services/speech/fake_tts_service.dart';

/// Test seam that **is** a [NoteEditorBloc] (so
/// `BlocProvider<NoteEditorBloc>` accepts it without a generic-type
/// mismatch) but freezes handler logic: [add] records the event into
/// [events] and skips the real `_on*` handler chain.
///
/// Use this when a widget test needs to assert "tap dispatches X" against
/// a known-shape state without coupling to handler internals — handler
/// behavior is exhaustively tested in `note_editor_bloc_test.dart`. For
/// tests that need real handler outcomes (e.g. `audio_capture_button_test`),
/// construct the production [NoteEditorBloc] with fakes via that file's
/// `_readyBloc` builder.
///
/// Centralised here so a new required constructor parameter on
/// [NoteEditorBloc] (Spec 18 ships `LlmService`, Spec 21 ships
/// `WhisperService`, etc.) only needs to be added in one place. Spec 15
/// silently broke `audio_capture_button_test.dart` and Spec 16 silently
/// broke the three `dictation_button` / `read_aloud_button` /
/// `read_aloud_overlay` siblings — the recurrence stops here.
class RecordingNoteEditorBloc extends NoteEditorBloc {
  RecordingNoteEditorBloc({NoteEditorState? initial})
      : super(
          repository: FakeNotesRepository(),
          identityRepository: FakeNotiIdentityRepository(),
          audio: FakeAudioRepository(),
          permissions: FakePermissionsService(),
          stt: FakeSttService(),
          tts: FakeTtsService(),
          cancelNotification: _noopCancel,
        ) {
    if (initial != null) emit(initial);
  }

  final List<NoteEditorEvent> events = [];

  @override
  void add(NoteEditorEvent event) {
    events.add(event);
    // Deliberately skip `super.add` — handler logic is owned by
    // note_editor_bloc_test.dart.
  }

  /// Pushes [next] as the current state without dispatching an event.
  /// Useful for widget tests that re-render the harness under a different
  /// state shape without invoking handler logic.
  void push(NoteEditorState next) => emit(next);

  static void _noopCancel(int id) {}
}
