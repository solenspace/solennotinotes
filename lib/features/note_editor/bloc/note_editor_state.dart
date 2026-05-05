import 'package:equatable/equatable.dart';
import 'package:noti_notes_app/models/note.dart';

enum NoteEditorStatus { initial, loading, ready, notFound, saving, error }

class NoteEditorState extends Equatable {
  const NoteEditorState({
    this.status = NoteEditorStatus.initial,
    this.note,
    this.popRequested = false,
    this.errorMessage,
  });

  final NoteEditorStatus status;
  final Note? note;

  /// One-shot signal: when true, the screen should pop the route. The next
  /// state emission will reset this to false.
  final bool popRequested;

  final String? errorMessage;

  NoteEditorState copyWith({
    NoteEditorStatus? status,
    Note? note,
    bool? popRequested,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NoteEditorState(
      status: status ?? this.status,
      note: note ?? this.note,
      popRequested: popRequested ?? false,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, note, popRequested, errorMessage];
}
