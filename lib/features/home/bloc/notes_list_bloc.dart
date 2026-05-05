import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';
import 'package:noti_notes_app/services/notifications/notifications_service.dart';

import 'notes_list_event.dart';
import 'notes_list_state.dart';

typedef CancelNotification = void Function(int id);

class NotesListBloc extends Bloc<NotesListEvent, NotesListState> {
  NotesListBloc({
    required NotesRepository repository,
    CancelNotification? cancelNotification,
  })  : _repository = repository,
        _cancelNotification = cancelNotification ?? LocalNotificationService.cancelNotification,
        super(const NotesListState()) {
    on<NotesListSubscribed>(_onSubscribed);
    on<PinToggled>(_onPinToggled);
    on<NoteDeleted>(_onNoteDeleted);
    on<NoteBlocksReplaced>(_onNoteBlocksReplaced);
  }

  final NotesRepository _repository;
  final CancelNotification _cancelNotification;

  Future<void> _onSubscribed(
    NotesListSubscribed event,
    Emitter<NotesListState> emit,
  ) async {
    emit(state.copyWith(status: NotesListStatus.loading, clearError: true));
    await emit.forEach<List<Note>>(
      _repository.watchAll(),
      onData: (notes) => state.copyWith(
        status: NotesListStatus.ready,
        notes: _sortDesc(notes),
        clearError: true,
      ),
      onError: (error, _) => state.copyWith(
        status: NotesListStatus.failure,
        errorMessage: error.toString(),
      ),
    );
  }

  Future<void> _onPinToggled(
    PinToggled event,
    Emitter<NotesListState> emit,
  ) async {
    final note = _findOrNull(event.id);
    if (note == null) return;
    note.isPinned = !note.isPinned;
    await _repository.save(note);
  }

  Future<void> _onNoteDeleted(
    NoteDeleted event,
    Emitter<NotesListState> emit,
  ) async {
    final index = state.notes.indexWhere((n) => n.id == event.id);
    if (index < 0) return;
    _cancelNotification(index);
    await _repository.delete(event.id);
  }

  Future<void> _onNoteBlocksReplaced(
    NoteBlocksReplaced event,
    Emitter<NotesListState> emit,
  ) async {
    final note = _findOrNull(event.id);
    if (note == null) return;
    note.blocks = event.blocks;
    await _repository.save(note);
  }

  Note? _findOrNull(String id) {
    for (final note in state.notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  static List<Note> _sortDesc(List<Note> notes) {
    final copy = [...notes];
    copy.sort((a, b) => b.dateCreated.compareTo(a.dateCreated));
    return copy;
  }
}
