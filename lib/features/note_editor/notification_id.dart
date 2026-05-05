/// Maps a note id to a positive 31-bit notification id. Shared between
/// `NoteEditorBloc._onNoteDeleted` and `reminder_sheet.dart` so a reminder
/// scheduled in the editor is correctly cancelled when the note is deleted.
///
/// The legacy `Notes` provider used the note's current list-index as the
/// notification id (open question 12 in progress-tracker); this scheme
/// removes the index dependency for the editor's own reminders.
int notificationIdForNote(String noteId) => noteId.hashCode & 0x7fffffff;
