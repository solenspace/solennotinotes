import 'dart:async';

import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';

/// Test double for [NotesRepository] backed by an in-memory list and a
/// broadcast controller. `watchAll()` yields the current snapshot first,
/// then forwards every controller event.
class FakeNotesRepository implements NotesRepository {
  final StreamController<List<Note>> _controller = StreamController<List<Note>>.broadcast();
  List<Note> _store = const [];

  final List<String> deletedIds = [];
  final List<Note> savedNotes = [];
  bool clearCalled = false;

  void emit(List<Note> notes) {
    _store = List<Note>.unmodifiable(notes);
    _controller.add(_store);
  }

  @override
  Future<void> init() async {}

  @override
  Future<List<Note>> getAll() async => _store;

  @override
  Stream<List<Note>> watchAll() async* {
    yield _store;
    yield* _controller.stream;
  }

  @override
  Future<void> save(Note note) async {
    savedNotes.add(note);
    final next = [..._store.where((n) => n.id != note.id), note];
    _store = List<Note>.unmodifiable(next);
    _controller.add(_store);
  }

  @override
  Future<void> saveAll(Iterable<Note> notes) async {
    for (final n in notes) {
      await save(n);
    }
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    _store = List<Note>.unmodifiable(_store.where((n) => n.id != id));
    _controller.add(_store);
  }

  @override
  Future<void> deleteAll(Iterable<String> ids) async {
    for (final id in ids) {
      await delete(id);
    }
  }

  @override
  Future<void> clear() async {
    clearCalled = true;
    _store = const [];
    _controller.add(_store);
  }

  Future<void> dispose() => _controller.close();

  bool get hasListener => _controller.hasListener;
}
