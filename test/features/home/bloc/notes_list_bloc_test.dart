import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/features/home/bloc/notes_list_bloc.dart';
import 'package:noti_notes_app/features/home/bloc/notes_list_event.dart';
import 'package:noti_notes_app/features/home/bloc/notes_list_state.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/repositories/notes/notes_repository.dart';

import '../../../repositories/notes/fake_notes_repository.dart';

Note _buildNote({
  required String id,
  String title = 'title',
  Set<String>? tags,
  DateTime? dateCreated,
  bool isPinned = false,
  List<Map<String, dynamic>>? blocks,
}) {
  return Note(
    tags ?? const {'work'},
    null,
    null,
    const [],
    null,
    null,
    id: id,
    title: title,
    content: 'content',
    dateCreated: dateCreated ?? DateTime(2026, 5, 4, 12),
    colorBackground: const Color(0xFFEDE6D6),
    fontColor: const Color(0xFF1C1B1A),
    hasGradient: false,
    isPinned: isPinned,
    blocks: blocks,
  );
}

Future<List<NotesListState>> _drain(
  NotesListBloc bloc,
  Future<void> Function() act, {
  int expectedCount = 1,
  Duration timeout = const Duration(seconds: 1),
}) async {
  final emissions = <NotesListState>[];
  final sub = bloc.stream.listen(emissions.add);
  await act();
  final deadline = DateTime.now().add(timeout);
  while (emissions.length < expectedCount && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await sub.cancel();
  return emissions;
}

void main() {
  late FakeNotesRepository fake;
  late List<int> cancelledNotificationIds;

  NotesListBloc buildBloc({NotesRepository? repository}) => NotesListBloc(
        repository: repository ?? fake,
        cancelNotification: cancelledNotificationIds.add,
      );

  setUp(() {
    fake = FakeNotesRepository();
    cancelledNotificationIds = <int>[];
  });

  tearDown(() async {
    await fake.dispose();
  });

  group('NotesListBloc', () {
    test('starts in initial status with empty notes', () {
      final bloc = buildBloc();
      expect(bloc.state.status, NotesListStatus.initial);
      expect(bloc.state.notes, isEmpty);
      bloc.close();
    });

    test('NotesListSubscribed emits loading then ready with sorted notes', () async {
      final older = _buildNote(id: 'old', dateCreated: DateTime(2026, 1, 1));
      final newer = _buildNote(id: 'new', dateCreated: DateTime(2026, 5, 1));
      fake.emit([older, newer]);

      final bloc = buildBloc();
      final emissions = await _drain(
        bloc,
        () async => bloc.add(const NotesListSubscribed()),
        expectedCount: 2,
      );

      expect(emissions, hasLength(greaterThanOrEqualTo(2)));
      expect(emissions[0].status, NotesListStatus.loading);
      final ready = emissions.firstWhere((s) => s.status == NotesListStatus.ready);
      expect(ready.notes.map((n) => n.id), ['new', 'old']);

      await bloc.close();
    });

    test('PinToggled saves the note with the flipped pin flag', () async {
      final note = _buildNote(id: 'a', isPinned: false);
      fake.emit([note]);
      final bloc = buildBloc();

      await _drain(
        bloc,
        () async => bloc.add(const NotesListSubscribed()),
        expectedCount: 2,
      );

      bloc.add(const PinToggled('a'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fake.savedNotes, hasLength(1));
      expect(fake.savedNotes.single.id, 'a');
      expect(fake.savedNotes.single.isPinned, isTrue);
      expect(bloc.state.notes.single.isPinned, isTrue);

      await bloc.close();
    });

    test('PinToggled with unknown id is a no-op', () async {
      fake.emit([_buildNote(id: 'a')]);
      final bloc = buildBloc();
      await _drain(
        bloc,
        () async => bloc.add(const NotesListSubscribed()),
        expectedCount: 2,
      );

      bloc.add(const PinToggled('does-not-exist'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fake.savedNotes, isEmpty);
      await bloc.close();
    });

    test('NoteDeleted calls repository.delete and drops the note from state', () async {
      fake.emit([_buildNote(id: 'a'), _buildNote(id: 'b')]);
      final bloc = buildBloc();
      await _drain(
        bloc,
        () async => bloc.add(const NotesListSubscribed()),
        expectedCount: 2,
      );

      bloc.add(const NoteDeleted('a'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fake.deletedIds, ['a']);
      expect(cancelledNotificationIds, [0]);
      expect(bloc.state.notes.map((n) => n.id), ['b']);

      await bloc.close();
    });

    test('NoteDeleted with unknown id is a no-op', () async {
      fake.emit([_buildNote(id: 'a')]);
      final bloc = buildBloc();
      await _drain(
        bloc,
        () async => bloc.add(const NotesListSubscribed()),
        expectedCount: 2,
      );

      bloc.add(const NoteDeleted('does-not-exist'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fake.deletedIds, isEmpty);
      expect(cancelledNotificationIds, isEmpty);
      await bloc.close();
    });

    test('NoteBlocksReplaced saves the note with new blocks', () async {
      fake.emit([_buildNote(id: 'a', blocks: const [])]);
      final bloc = buildBloc();
      await _drain(
        bloc,
        () async => bloc.add(const NotesListSubscribed()),
        expectedCount: 2,
      );

      const newBlocks = [
        {'type': 'checklist', 'id': 'b1', 'checked': true, 'text': 'done'},
      ];
      bloc.add(const NoteBlocksReplaced('a', newBlocks));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fake.savedNotes, hasLength(1));
      expect(fake.savedNotes.single.id, 'a');
      expect(fake.savedNotes.single.blocks, newBlocks);

      await bloc.close();
    });

    test('errors on the repository stream surface as failure status', () async {
      final bloc = buildBloc(repository: _ErroringRepository());
      final emissions = await _drain(
        bloc,
        () async => bloc.add(const NotesListSubscribed()),
        expectedCount: 2,
      );

      final failure = emissions.firstWhere((s) => s.status == NotesListStatus.failure);
      expect(failure.errorMessage, contains('boom'));

      await bloc.close();
    });

    test('close releases the repository stream subscription', () async {
      fake.emit([_buildNote(id: 'a')]);
      final bloc = buildBloc();
      await _drain(
        bloc,
        () async => bloc.add(const NotesListSubscribed()),
        expectedCount: 2,
      );

      expect(fake.hasListener, isTrue);
      await bloc.close();
      // hasListener can lag one microtask after close(); settle then verify.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fake.hasListener, isFalse);
    });
  });
}

class _ErroringRepository implements NotesRepository {
  @override
  Stream<List<Note>> watchAll() async* {
    throw StateError('boom');
  }

  @override
  Future<void> init() async {}
  @override
  Future<List<Note>> getAll() async => const [];
  @override
  Future<void> save(Note note) async {}
  @override
  Future<void> saveAll(Iterable<Note> notes) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> deleteAll(Iterable<String> ids) async {}
  @override
  Future<void> clear() async {}
}
