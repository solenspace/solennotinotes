import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/models/note.dart';

import '../../../repositories/audio/fake_audio_repository.dart';
import '../../../repositories/noti_identity/fake_noti_identity_repository.dart';
import '../../../repositories/notes/fake_notes_repository.dart';
import '../../../services/permissions/fake_permissions_service.dart';
import '../../../services/speech/fake_stt_service.dart';
import '../../../services/speech/fake_tts_service.dart';

/// Bundle of fakes the overlay-picker and editor goldens share. Held by the
/// caller so tear-down can dispose them.
class GoldenEditorEnv {
  GoldenEditorEnv({required this.notes, required this.bloc});
  final FakeNotesRepository notes;
  final NoteEditorBloc bloc;
}

/// Constructs a real [NoteEditorBloc] wired to the existing test fakes,
/// pre-seeded with [note], and dispatches [EditorOpened] so the state
/// settles to `ready` with `note` non-null. The caller is expected to
/// `await tester.pump()` once after `pumpScene` so the bloc handler runs.
GoldenEditorEnv seededEditorEnv(Note note) {
  final notes = FakeNotesRepository();
  notes.emit([note]);
  final bloc = NoteEditorBloc(
    repository: notes,
    identityRepository: FakeNotiIdentityRepository(),
    audio: FakeAudioRepository(),
    permissions: FakePermissionsService(),
    stt: FakeSttService(),
    tts: FakeTtsService(),
    cancelNotification: (_) {},
  )..add(EditorOpened(noteId: note.id));
  return GoldenEditorEnv(notes: notes, bloc: bloc);
}
