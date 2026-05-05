import 'package:equatable/equatable.dart';
import 'package:noti_notes_app/models/note.dart';

enum NotesListStatus { initial, loading, ready, failure }

class NotesListState extends Equatable {
  const NotesListState({
    this.status = NotesListStatus.initial,
    this.notes = const [],
    this.errorMessage,
  });

  final NotesListStatus status;
  final List<Note> notes;
  final String? errorMessage;

  List<Note> get pinnedNotes => notes.where((n) => n.isPinned).toList(growable: false);

  List<Note> get unpinnedNotes => notes.where((n) => !n.isPinned).toList(growable: false);

  NotesListState copyWith({
    NotesListStatus? status,
    List<Note>? notes,
    String? errorMessage,
    bool clearError = false,
  }) {
    return NotesListState(
      status: status ?? this.status,
      notes: notes ?? this.notes,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, notes, errorMessage];
}
