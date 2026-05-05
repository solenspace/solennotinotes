import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/features/note_editor/note_type.dart';
import 'package:noti_notes_app/features/note_editor/notification_id.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';

import '../../../repositories/notes/fake_notes_repository.dart';

Note _buildNote({
  required String id,
  String title = 'title',
  Set<String>? tags,
  DateTime? dateCreated,
  bool isPinned = false,
  List<Map<String, dynamic>>? blocks,
  List<Map<String, dynamic>>? todoList,
  File? imageFile,
  DateTime? reminder,
  String? patternImage,
  bool hasGradient = false,
  LinearGradient? gradient,
  Color colorBackground = const Color(0xFFEDE6D6),
  Color fontColor = const Color(0xFF1C1B1A),
  DisplayMode displayMode = DisplayMode.normal,
}) {
  return Note(
    tags ?? <String>{'work'},
    imageFile,
    patternImage,
    todoList ?? <Map<String, dynamic>>[],
    reminder,
    gradient,
    id: id,
    title: title,
    content: 'content',
    dateCreated: dateCreated ?? DateTime(2026, 5, 4, 12),
    colorBackground: colorBackground,
    fontColor: fontColor,
    hasGradient: hasGradient,
    isPinned: isPinned,
    displayMode: displayMode,
    blocks: blocks,
  );
}

/// Test double for [ImagePickerService] that records `removeImage(File)`
/// invocations without touching the filesystem.
class _RecordingImageService implements ImagePickerService {
  final List<String> removedPaths = [];

  @override
  Future<File?> pickImage(ImageSource source, int quality) {
    throw UnimplementedError('pickImage should not be called in these tests');
  }

  @override
  Future<void> removeImage(File image) async {
    removedPaths.add(image.path);
  }
}

/// Drains up to [expectedCount] state emissions from the bloc, calling
/// [act] after subscribing. Mirrors the helper in
/// `notes_list_bloc_test.dart`.
Future<List<NoteEditorState>> _drain(
  NoteEditorBloc bloc,
  Future<void> Function() act, {
  int expectedCount = 1,
  Duration timeout = const Duration(seconds: 1),
}) async {
  final emissions = <NoteEditorState>[];
  final sub = bloc.stream.listen(emissions.add);
  await act();
  final deadline = DateTime.now().add(timeout);
  while (emissions.length < expectedCount && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await sub.cancel();
  return emissions;
}

/// Builds a bloc and brings it to `ready` with [seed] as the working note.
/// `EditorOpened(noteId: seed.id)` reads from `fake.getAll()` and emits
/// loading → ready, so we drain those before returning.
Future<NoteEditorBloc> _readyBloc({
  required FakeNotesRepository fake,
  required _RecordingImageService imageService,
  required List<int> cancelledNotificationIds,
  required Note seed,
}) async {
  fake.emit([seed]);
  final bloc = NoteEditorBloc(
    repository: fake,
    imageService: imageService,
    cancelNotification: cancelledNotificationIds.add,
  );
  await _drain(
    bloc,
    () async => bloc.add(EditorOpened(noteId: seed.id)),
    expectedCount: 2,
  );
  // Pre-populating the fake counts as a save into the test double's
  // recording list (because `emit` is the test seed); reset so each test
  // sees only the saves it caused.
  fake.savedNotes.clear();
  return bloc;
}

void main() {
  late FakeNotesRepository fake;
  late _RecordingImageService imageService;
  late List<int> cancelledNotificationIds;

  setUp(() {
    fake = FakeNotesRepository();
    imageService = _RecordingImageService();
    cancelledNotificationIds = <int>[];
  });

  tearDown(() async {
    await fake.dispose();
  });

  group('NoteEditorBloc — initial state', () {
    test('starts in initial status with no note', () {
      final bloc = NoteEditorBloc(
        repository: fake,
        imageService: imageService,
        cancelNotification: cancelledNotificationIds.add,
      );
      expect(bloc.state.status, NoteEditorStatus.initial);
      expect(bloc.state.note, isNull);
      expect(bloc.state.popRequested, isFalse);
      bloc.close();
    });
  });

  group('NoteEditorBloc — EditorOpened', () {
    test('with null noteId emits ready with a fresh content note', () async {
      final bloc = NoteEditorBloc(
        repository: fake,
        imageService: imageService,
        cancelNotification: cancelledNotificationIds.add,
      );
      final emissions = await _drain(
        bloc,
        () async => bloc.add(const EditorOpened()),
        expectedCount: 2,
      );

      expect(emissions[0].status, NoteEditorStatus.loading);
      expect(emissions.last.status, NoteEditorStatus.ready);
      expect(emissions.last.note, isNotNull);
      expect(emissions.last.note!.title, '');
      expect(emissions.last.note!.blocks, isEmpty);
      expect(emissions.last.note!.todoList, isEmpty);
      expect(emissions.last.note!.displayMode, DisplayMode.normal);
      // Blank notes are not auto-saved; first content event triggers save.
      expect(fake.savedNotes, isEmpty);
      await bloc.close();
    });

    test('with null noteId and todo type seeds an empty checklist task', () async {
      final bloc = NoteEditorBloc(
        repository: fake,
        imageService: imageService,
        cancelNotification: cancelledNotificationIds.add,
      );
      await _drain(
        bloc,
        () async => bloc.add(const EditorOpened(noteType: NoteType.todo)),
        expectedCount: 2,
      );

      expect(bloc.state.note?.displayMode, DisplayMode.withTodoList);
      expect(bloc.state.note?.todoList, hasLength(1));
      expect(bloc.state.note?.todoList.single['content'], '');
      expect(bloc.state.note?.todoList.single['isChecked'], false);
      await bloc.close();
    });

    test('with existing noteId loads the matching note from the repository', () async {
      final existing = _buildNote(id: 'a', title: 'hello');
      fake.emit([existing]);

      final bloc = NoteEditorBloc(
        repository: fake,
        imageService: imageService,
        cancelNotification: cancelledNotificationIds.add,
      );
      final emissions = await _drain(
        bloc,
        () async => bloc.add(const EditorOpened(noteId: 'a')),
        expectedCount: 2,
      );

      expect(emissions.last.status, NoteEditorStatus.ready);
      expect(emissions.last.note?.id, 'a');
      expect(emissions.last.note?.title, 'hello');
      await bloc.close();
    });

    test('with missing noteId emits notFound', () async {
      fake.emit([_buildNote(id: 'a')]);

      final bloc = NoteEditorBloc(
        repository: fake,
        imageService: imageService,
        cancelNotification: cancelledNotificationIds.add,
      );
      final emissions = await _drain(
        bloc,
        () async => bloc.add(const EditorOpened(noteId: 'missing')),
        expectedCount: 2,
      );

      expect(emissions.last.status, NoteEditorStatus.notFound);
      expect(emissions.last.note, isNull);
      await bloc.close();
    });
  });

  group('NoteEditorBloc — title and content', () {
    test('TitleChanged updates title and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', title: 'before'),
      );

      await _drain(bloc, () async => bloc.add(const TitleChanged('after')));

      expect(fake.savedNotes.single.title, 'after');
      expect(bloc.state.note?.title, 'after');
      await bloc.close();
    });

    test('TitleChanged is a no-op when state.note is null', () async {
      final bloc = NoteEditorBloc(
        repository: fake,
        imageService: imageService,
        cancelNotification: cancelledNotificationIds.add,
      );
      bloc.add(const TitleChanged('after'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fake.savedNotes, isEmpty);
      await bloc.close();
    });

    test('BlocksReplaced replaces blocks and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );
      const newBlocks = <Map<String, dynamic>>[
        {'type': 'text', 'id': 'b1', 'text': 'hello'},
      ];

      await _drain(bloc, () async => bloc.add(const BlocksReplaced(newBlocks)));

      expect(fake.savedNotes.single.blocks, newBlocks);
      await bloc.close();
    });
  });

  group('NoteEditorBloc — tags', () {
    test('TagAdded adds a tag and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', tags: <String>{}),
      );

      await _drain(bloc, () async => bloc.add(const TagAdded('idea')));

      expect(fake.savedNotes.single.tags, contains('idea'));
      await bloc.close();
    });

    test('TagRemovedAtIndex removes the tag at the given index and saves', () async {
      // Sets are insertion-ordered; index 1 should be 'b'.
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', tags: <String>{'a', 'b', 'c'}),
      );

      await _drain(bloc, () async => bloc.add(const TagRemovedAtIndex(1)));

      expect(fake.savedNotes.single.tags, equals(<String>{'a', 'c'}));
      await bloc.close();
    });

    test('TagRemovedAtIndex is a no-op for out-of-range indices', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', tags: <String>{'only'}),
      );

      bloc.add(const TagRemovedAtIndex(5));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fake.savedNotes, isEmpty);
      await bloc.close();
    });
  });

  group('NoteEditorBloc — image', () {
    test('ImageSelected with no prior image just sets and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );

      await _drain(bloc, () async => bloc.add(ImageSelected(File('/tmp/new.jpg'))));

      expect(imageService.removedPaths, isEmpty);
      expect(fake.savedNotes.single.imageFile?.path, '/tmp/new.jpg');
      await bloc.close();
    });

    test('ImageSelected replacing a different image cleans up the old file', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', imageFile: File('/tmp/old.jpg')),
      );

      await _drain(bloc, () async => bloc.add(ImageSelected(File('/tmp/new.jpg'))));

      expect(imageService.removedPaths, ['/tmp/old.jpg']);
      expect(fake.savedNotes.single.imageFile?.path, '/tmp/new.jpg');
      await bloc.close();
    });

    test('ImageSelected with the same path skips the cleanup call', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', imageFile: File('/tmp/same.jpg')),
      );

      await _drain(bloc, () async => bloc.add(ImageSelected(File('/tmp/same.jpg'))));

      expect(imageService.removedPaths, isEmpty);
      await bloc.close();
    });

    test('ImageRemoved deletes file and clears the field', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', imageFile: File('/tmp/to-remove.jpg')),
      );

      await _drain(bloc, () async => bloc.add(const ImageRemoved()));

      expect(imageService.removedPaths, ['/tmp/to-remove.jpg']);
      expect(fake.savedNotes.single.imageFile, isNull);
      await bloc.close();
    });
  });

  group('NoteEditorBloc — appearance', () {
    test('BackgroundColorChanged updates colorBackground and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );

      await _drain(
        bloc,
        () async => bloc.add(const BackgroundColorChanged(Color(0xFF112233))),
      );

      expect(fake.savedNotes.single.colorBackground, const Color(0xFF112233));
      await bloc.close();
    });

    test('PatternImageSet stores the asset key and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );

      await _drain(bloc, () async => bloc.add(const PatternImageSet('grid.png')));

      expect(fake.savedNotes.single.patternImage, 'grid.png');
      await bloc.close();
    });

    test('PatternImageRemoved clears the pattern and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', patternImage: 'old.png'),
      );

      await _drain(bloc, () async => bloc.add(const PatternImageRemoved()));

      expect(fake.savedNotes.single.patternImage, isNull);
      await bloc.close();
    });

    test('FontColorChanged updates fontColor and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );

      await _drain(
        bloc,
        () async => bloc.add(const FontColorChanged(Color(0xFFAA0000))),
      );

      expect(fake.savedNotes.single.fontColor, const Color(0xFFAA0000));
      await bloc.close();
    });

    test('DisplayModeChanged updates displayMode and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );

      await _drain(
        bloc,
        () async => bloc.add(const DisplayModeChanged(DisplayMode.withImage)),
      );

      expect(fake.savedNotes.single.displayMode, DisplayMode.withImage);
      await bloc.close();
    });

    test('GradientChanged stores the gradient and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );
      const gradient = LinearGradient(colors: [Color(0xFF000000), Color(0xFFFFFFFF)]);

      await _drain(bloc, () async => bloc.add(const GradientChanged(gradient)));

      expect(fake.savedNotes.single.gradient, gradient);
      await bloc.close();
    });

    test('GradientToggled flips hasGradient and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', hasGradient: false),
      );

      await _drain(bloc, () async => bloc.add(const GradientToggled()));

      expect(fake.savedNotes.single.hasGradient, isTrue);
      await bloc.close();
    });
  });

  group('NoteEditorBloc — reminders', () {
    test('ReminderSet stores the date and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );
      final date = DateTime(2026, 6, 1, 9);

      await _drain(bloc, () async => bloc.add(ReminderSet(date)));

      expect(fake.savedNotes.single.reminder, date);
      await bloc.close();
    });

    test('ReminderRemoved clears the date and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', reminder: DateTime(2026, 6, 1)),
      );

      await _drain(bloc, () async => bloc.add(const ReminderRemoved()));

      expect(fake.savedNotes.single.reminder, isNull);
      await bloc.close();
    });
  });

  group('NoteEditorBloc — todos', () {
    test('TaskAdded appends an empty unchecked task and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', todoList: []),
      );

      await _drain(bloc, () async => bloc.add(const TaskAdded()));

      expect(fake.savedNotes.single.todoList, hasLength(1));
      expect(fake.savedNotes.single.todoList.single['content'], '');
      expect(fake.savedNotes.single.todoList.single['isChecked'], false);
      await bloc.close();
    });

    test('TaskToggledAtIndex flips isChecked and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(
          id: 'a',
          todoList: [
            {'content': 'one', 'isChecked': false},
          ],
        ),
      );

      await _drain(bloc, () async => bloc.add(const TaskToggledAtIndex(0)));

      expect(fake.savedNotes.single.todoList[0]['isChecked'], isTrue);
      await bloc.close();
    });

    test('TaskToggledAtIndex with out-of-range index is a no-op', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', todoList: []),
      );

      bloc.add(const TaskToggledAtIndex(0));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fake.savedNotes, isEmpty);
      await bloc.close();
    });

    test('TaskRemovedAtIndex removes the task and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(
          id: 'a',
          todoList: [
            {'content': 'keep', 'isChecked': false},
            {'content': 'drop', 'isChecked': false},
          ],
        ),
      );

      await _drain(bloc, () async => bloc.add(const TaskRemovedAtIndex(1)));

      expect(fake.savedNotes.single.todoList, hasLength(1));
      expect(fake.savedNotes.single.todoList.single['content'], 'keep');
      await bloc.close();
    });

    test('TaskContentUpdatedAtIndex writes content and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(
          id: 'a',
          todoList: [
            {'content': 'old', 'isChecked': false},
          ],
        ),
      );

      await _drain(
        bloc,
        () async => bloc.add(const TaskContentUpdatedAtIndex(index: 0, content: 'new')),
      );

      expect(fake.savedNotes.single.todoList[0]['content'], 'new');
      await bloc.close();
    });
  });

  group('NoteEditorBloc — pin and delete', () {
    test('PinToggled flips isPinned and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', isPinned: false),
      );

      await _drain(bloc, () async => bloc.add(const PinToggled()));

      expect(fake.savedNotes.single.isPinned, isTrue);
      await bloc.close();
    });

    test('NoteDeleted cancels the notification, deletes, and signals popRequested', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );

      final emissions = await _drain(
        bloc,
        () async => bloc.add(const NoteDeleted()),
      );

      expect(fake.deletedIds, ['a']);
      expect(cancelledNotificationIds, [notificationIdForNote('a')]);
      expect(emissions.last.popRequested, isTrue);
      await bloc.close();
    });

    test('popRequested resets to false on the next state-bearing emission', () async {
      final bloc = await _readyBloc(
        fake: fake,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );

      // Delete sets popRequested = true.
      await _drain(bloc, () async => bloc.add(const NoteDeleted()));
      expect(bloc.state.popRequested, isTrue);

      // The note is gone now; subsequent events early-return without
      // emitting. To verify the one-shot reset, simulate re-entry by
      // dispatching EditorOpened with a fresh note id (the fake still has
      // no notes after delete, so this lands in `notFound`); the emission
      // clears the flag because copyWith resets popRequested unless asked.
      await _drain(
        bloc,
        () async => bloc.add(const EditorOpened(noteId: 'new')),
        expectedCount: 2,
      );
      expect(bloc.state.popRequested, isFalse);

      await bloc.close();
    });
  });
}
