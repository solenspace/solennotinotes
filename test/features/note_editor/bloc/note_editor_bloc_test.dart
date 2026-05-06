import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_bloc.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_event.dart';
import 'package:noti_notes_app/features/note_editor/bloc/note_editor_state.dart';
import 'package:noti_notes_app/features/note_editor/note_type.dart';
import 'package:noti_notes_app/features/note_editor/notification_id.dart';
import 'package:noti_notes_app/models/editor_block.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/note_overlay.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';
import 'package:noti_notes_app/services/permissions/permission_result.dart';
import 'package:noti_notes_app/theme/curated_palettes.dart';
import 'package:noti_notes_app/theme/noti_pattern_key.dart';
import 'package:noti_notes_app/theme/noti_theme_overlay.dart';
import 'package:noti_notes_app/theme/tokens/primitives.dart';

import '../../../repositories/audio/fake_audio_repository.dart';
import '../../../repositories/noti_identity/fake_noti_identity_repository.dart';
import '../../../repositories/notes/fake_notes_repository.dart';
import '../../../services/permissions/fake_permissions_service.dart';
import '../../../services/speech/fake_stt_service.dart';

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
  required FakeNotiIdentityRepository identityRepository,
  required _RecordingImageService imageService,
  required List<int> cancelledNotificationIds,
  required Note seed,
  FakeAudioRepository? audioRepository,
  FakePermissionsService? permissionsService,
  FakeSttService? sttService,
}) async {
  fake.emit([seed]);
  final bloc = NoteEditorBloc(
    repository: fake,
    identityRepository: identityRepository,
    audio: audioRepository ?? FakeAudioRepository(),
    permissions: permissionsService ?? FakePermissionsService(),
    stt: sttService ?? FakeSttService(),
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

/// Deterministic identity that drives `OverlayResetToIdentityDefault` and
/// `OverlayConvertToMine` in tests. Uses curated palette index 8 ("Slate")
/// so the surface and accent slots are recognizable in expectations.
NotiIdentity _testIdentity({String accent = '✦', String tagline = 'morning notes'}) {
  final palette = kCuratedPalettes[8];
  return NotiIdentity(
    id: 'identity-test',
    displayName: 'Tester',
    bornDate: DateTime(2000, 1, 1),
    signaturePalette: [palette.surface, palette.surfaceVariant, palette.accent, palette.onAccent],
    signaturePatternKey: NotiPatternKey.polygons.name,
    signatureAccent: accent,
    signatureTagline: tagline,
  );
}

void main() {
  late FakeNotesRepository fake;
  late FakeNotiIdentityRepository identityRepository;
  late _RecordingImageService imageService;
  late List<int> cancelledNotificationIds;

  setUp(() {
    fake = FakeNotesRepository();
    identityRepository = FakeNotiIdentityRepository();
    identityRepository.emit(_testIdentity());
    imageService = _RecordingImageService();
    cancelledNotificationIds = <int>[];
  });

  tearDown(() async {
    await fake.dispose();
    await identityRepository.dispose();
  });

  group('NoteEditorBloc — initial state', () {
    test('starts in initial status with no note', () {
      final bloc = NoteEditorBloc(
        repository: fake,
        identityRepository: identityRepository,
        audio: FakeAudioRepository(),
        permissions: FakePermissionsService(),
        stt: FakeSttService(),
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
        identityRepository: identityRepository,
        audio: FakeAudioRepository(),
        permissions: FakePermissionsService(),
        stt: FakeSttService(),
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
        identityRepository: identityRepository,
        audio: FakeAudioRepository(),
        permissions: FakePermissionsService(),
        stt: FakeSttService(),
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
        identityRepository: identityRepository,
        audio: FakeAudioRepository(),
        permissions: FakePermissionsService(),
        stt: FakeSttService(),
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
        identityRepository: identityRepository,
        audio: FakeAudioRepository(),
        permissions: FakePermissionsService(),
        stt: FakeSttService(),
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
        audio: FakeAudioRepository(),
        permissions: FakePermissionsService(),
        stt: FakeSttService(),
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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
        identityRepository: identityRepository,
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

  group('NoteEditorBloc — OverlayPaletteChanged', () {
    test('writes surface, fontColor, and clears gradient', () async {
      const overlay = NotiThemeOverlay(
        surface: Color(0xFF2D2D2D),
        surfaceVariant: Color(0xFF383838),
        accent: Color(0xFFE5B26B),
        onAccent: Color(0xFF1A1A1A),
        onSurface: Color(0xFFEDEDED),
      );
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(
          id: 'a',
          hasGradient: true,
          gradient: const LinearGradient(colors: [Color(0xFF000000), Color(0xFFFFFFFF)]),
        ),
      );

      await _drain(bloc, () async => bloc.add(const OverlayPaletteChanged(overlay)));

      final saved = fake.savedNotes.single;
      expect(saved.colorBackground, const Color(0xFF2D2D2D));
      expect(saved.fontColor, const Color(0xFFEDEDED));
      expect(saved.hasGradient, isFalse);
      expect(saved.gradient, isNull);
      await bloc.close();
    });

    test('derives fontColor via clampForReadability when overlay omits onSurface', () async {
      // Bone-toned surface → clamp picks the dark default.
      const overlay = NotiThemeOverlay(
        surface: Color(0xFFEDE6D6),
        surfaceVariant: Color(0xFFF5EFE2),
        accent: Color(0xFF4A8A7F),
        onAccent: Color(0xFF0F0F0F),
      );
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );

      await _drain(bloc, () async => bloc.add(const OverlayPaletteChanged(overlay)));

      expect(fake.savedNotes.single.fontColor, ColorPrimitives.inkOnLightSurface);
      await bloc.close();
    });

    test('is a no-op when state.note is null', () async {
      const overlay = NotiThemeOverlay(
        surface: Color(0xFF111111),
        surfaceVariant: Color(0xFF222222),
        accent: Color(0xFF333333),
        onAccent: Color(0xFFFFFFFF),
      );
      final bloc = NoteEditorBloc(
        repository: fake,
        identityRepository: identityRepository,
        audio: FakeAudioRepository(),
        permissions: FakePermissionsService(),
        stt: FakeSttService(),
        imageService: imageService,
        cancelNotification: cancelledNotificationIds.add,
      );
      bloc.add(const OverlayPaletteChanged(overlay));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fake.savedNotes, isEmpty);
      await bloc.close();
    });
  });

  group('NoteEditorBloc — OverlayPatternChanged', () {
    test('stores the enum name and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );

      await _drain(
        bloc,
        () async => bloc.add(const OverlayPatternChanged(NotiPatternKey.polygons)),
      );

      expect(fake.savedNotes.single.patternImage, NotiPatternKey.polygons.name);
      await bloc.close();
    });

    test('null patternKey clears patternImage', () async {
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a', patternImage: NotiPatternKey.waves.name),
      );

      await _drain(bloc, () async => bloc.add(const OverlayPatternChanged(null)));

      expect(fake.savedNotes.single.patternImage, isNull);
      await bloc.close();
    });
  });

  group('NoteEditorBloc — OverlayAccentChanged', () {
    test('clamps to the first user-perceived character', () async {
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );

      await _drain(bloc, () async => bloc.add(const OverlayAccentChanged('☼☾★')));

      expect(bloc.state.accentOverride, '☼');
      // No persistence: legacy schema has no place to store the glyph yet.
      expect(fake.savedNotes, isEmpty);
      await bloc.close();
    });

    test('empty string clears the override', () async {
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );

      await _drain(bloc, () async => bloc.add(const OverlayAccentChanged('★')));
      expect(bloc.state.accentOverride, '★');

      await _drain(bloc, () async => bloc.add(const OverlayAccentChanged('')));
      expect(bloc.state.accentOverride, isNull);
      await bloc.close();
    });

    test('is a no-op when state.note is null', () async {
      final bloc = NoteEditorBloc(
        repository: fake,
        identityRepository: identityRepository,
        audio: FakeAudioRepository(),
        permissions: FakePermissionsService(),
        stt: FakeSttService(),
        imageService: imageService,
        cancelNotification: cancelledNotificationIds.add,
      );
      bloc.add(const OverlayAccentChanged('★'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.accentOverride, isNull);
      await bloc.close();
    });
  });

  group('NoteEditorBloc — OverlayResetToIdentityDefault', () {
    test('writes the identity overlay onto the note and saves', () async {
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'a'),
      );

      await _drain(bloc, () async => bloc.add(const OverlayResetToIdentityDefault()));

      final saved = fake.savedNotes.single;
      final identityOverlay = kCuratedPalettes[8];
      expect(saved.colorBackground, identityOverlay.surface);
      expect(saved.patternImage, NotiPatternKey.polygons.name);
      expect(saved.hasGradient, isFalse);
      expect(saved.gradient, isNull);
      expect(bloc.state.accentOverride, '✦');
      await bloc.close();
    });

    test('is a no-op when state.note is null', () async {
      final bloc = NoteEditorBloc(
        repository: fake,
        identityRepository: identityRepository,
        audio: FakeAudioRepository(),
        permissions: FakePermissionsService(),
        stt: FakeSttService(),
        imageService: imageService,
        cancelNotification: cancelledNotificationIds.add,
      );
      bloc.add(const OverlayResetToIdentityDefault());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fake.savedNotes, isEmpty);
      await bloc.close();
    });
  });

  group('NoteEditorBloc — OverlayConvertToMine', () {
    test('replaces the synthesized overlay with the identity overlay', () async {
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(
          id: 'a',
          colorBackground: const Color(0xFFF5EFE2),
          fontColor: const Color(0xFF0F0F0F),
        ),
      );

      await _drain(bloc, () async => bloc.add(const OverlayConvertToMine()));

      final identityOverlay = kCuratedPalettes[8];
      expect(fake.savedNotes.single.colorBackground, identityOverlay.surface);
      // After conversion, the synthesized overlay's fromIdentityId is null
      // (legacy schema has no column for it), so the chip's render gate
      // collapses on the next rebuild.
      expect(bloc.state.note?.toOverlay().fromIdentityId, isNull);
      await bloc.close();
    });
  });

  group('NoteEditorBloc — audio capture', () {
    test('AudioCaptureRequested with mic granted starts a session', () async {
      final audio = FakeAudioRepository();
      final permissions = FakePermissionsService()..microphone = PermissionResult.granted;
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'n1'),
        audioRepository: audio,
        permissionsService: permissions,
      );

      await _drain(
        bloc,
        () async => bloc.add(const AudioCaptureRequested()),
        expectedCount: 1,
      );

      expect(audio.startedSessions, hasLength(1));
      expect(bloc.state.isCapturingAudio, isTrue);
      await audio.dispose();
      await bloc.close();
    });

    test('AudioCaptureRequested with mic denied → request → still denied → errorMessage', () async {
      final audio = FakeAudioRepository();
      final permissions = FakePermissionsService()..microphone = PermissionResult.denied;
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'n1'),
        audioRepository: audio,
        permissionsService: permissions,
      );

      // Two emissions: set errorMessage, then clear it (so the same denial
      // re-fires the snackbar listener on a retry — see bloc handler).
      final emissions = await _drain(
        bloc,
        () async => bloc.add(const AudioCaptureRequested()),
        expectedCount: 2,
      );

      expect(permissions.requestLog, contains('microphone'));
      expect(audio.startedSessions, isEmpty);
      expect(emissions.first.errorMessage, 'Microphone permission needed to record.');
      expect(emissions.last.errorMessage, isNull);
      await audio.dispose();
      await bloc.close();
    });

    test('AudioCaptureRequested with mic permanentlyDenied raises explainer flag', () async {
      final audio = FakeAudioRepository();
      final permissions = FakePermissionsService()..microphone = PermissionResult.permanentlyDenied;
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'n1'),
        audioRepository: audio,
        permissionsService: permissions,
      );

      final emissions = await _drain(
        bloc,
        () async => bloc.add(const AudioCaptureRequested()),
        expectedCount: 1,
      );

      // microphoneStatus returns permanentlyDenied → handler short-circuits
      // before requestMicrophone is even called.
      expect(permissions.requestLog, isEmpty);
      expect(audio.startedSessions, isEmpty);
      expect(emissions.last.audioPermissionExplainerRequested, isTrue);
      await audio.dispose();
      await bloc.close();
    });

    test('AudioCaptureStopped finalizes and emits committedAudioBlock', () async {
      final audio = FakeAudioRepository();
      final permissions = FakePermissionsService()..microphone = PermissionResult.granted;
      audio.finalizeReturn = AudioBlock(
        id: 'a1',
        path: '/fake/n1/a1.m4a',
        durationMs: 1234,
        amplitudePeaks: const [0.1, 0.2, 0.3],
      );
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'n1'),
        audioRepository: audio,
        permissionsService: permissions,
      );

      // Start session.
      await _drain(
        bloc,
        () async => bloc.add(const AudioCaptureRequested()),
        expectedCount: 1,
      );
      expect(bloc.state.isCapturingAudio, isTrue);

      // Stop → commit.
      final stopped = await _drain(
        bloc,
        () async => bloc.add(const AudioCaptureStopped()),
        expectedCount: 1,
      );
      expect(stopped.last.committedAudioBlock?.id, 'a1');
      expect(stopped.last.committedAudioBlock?.durationMs, 1234);
      expect(stopped.last.isCapturingAudio, isFalse);
      expect(stopped.last.currentAmplitude, isNull);
      // Bloc never mutates note.blocks itself — that's the screen's job.
      expect(fake.savedNotes, isEmpty);

      await audio.dispose();
      await bloc.close();
    });

    test('AudioCaptureCancelled discards the session and clears state', () async {
      final audio = FakeAudioRepository();
      final permissions = FakePermissionsService()..microphone = PermissionResult.granted;
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'n1'),
        audioRepository: audio,
        permissionsService: permissions,
      );

      await _drain(
        bloc,
        () async => bloc.add(const AudioCaptureRequested()),
        expectedCount: 1,
      );
      final sessionId = audio.startedSessions.single.id;

      final cancelled = await _drain(
        bloc,
        () async => bloc.add(const AudioCaptureCancelled()),
        expectedCount: 1,
      );

      expect(audio.cancelledIds, [sessionId]);
      expect(cancelled.last.isCapturingAudio, isFalse);
      expect(cancelled.last.currentAmplitude, isNull);
      expect(cancelled.last.committedAudioBlock, isNull);
      await audio.dispose();
      await bloc.close();
    });

    test('AudioBlockRemoved deletes the file (no note.blocks mutation)', () async {
      final audio = FakeAudioRepository();
      final permissions = FakePermissionsService();
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'n1'),
        audioRepository: audio,
        permissionsService: permissions,
      );

      bloc.add(const AudioBlockRemoved('a1'));
      // Allow the handler to run.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(audio.deletedAssets, hasLength(1));
      expect(audio.deletedAssets.single.noteId, 'n1');
      expect(audio.deletedAssets.single.audioId, 'a1');
      // Screen owns block-list mutations + persistence.
      expect(fake.savedNotes, isEmpty);
      await audio.dispose();
      await bloc.close();
    });

    test('close() cancels in-flight session and amplitude subscription', () async {
      final audio = FakeAudioRepository();
      final permissions = FakePermissionsService()..microphone = PermissionResult.granted;
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'n1'),
        audioRepository: audio,
        permissionsService: permissions,
      );

      await _drain(
        bloc,
        () async => bloc.add(const AudioCaptureRequested()),
        expectedCount: 1,
      );
      final sessionId = audio.startedSessions.single.id;

      await bloc.close();

      expect(audio.cancelledIds, [sessionId]);
      await audio.dispose();
    });
  });

  group('NoteEditorBloc — STT dictation', () {
    test('DictationStarted on offline-incapable device fires explainer flag', () async {
      final stt = FakeSttService(offlineCapable: false);
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'n1'),
        sttService: stt,
      );

      final emissions = await _drain(
        bloc,
        () async => bloc.add(const DictationStarted()),
        expectedCount: 1,
      );

      expect(emissions.single.dictationUnavailableExplainerRequested, isTrue);
      expect(emissions.single.isDictating, isFalse);
      expect(stt.startedLocaleIds, isEmpty);
      await stt.dispose();
      await bloc.close();
    });

    test('DictationStarted with mic permanently denied fires permission explainer', () async {
      final permissions = FakePermissionsService()..microphone = PermissionResult.permanentlyDenied;
      final stt = FakeSttService();
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'n1'),
        permissionsService: permissions,
        sttService: stt,
      );

      final emissions = await _drain(
        bloc,
        () async => bloc.add(const DictationStarted()),
        expectedCount: 1,
      );

      expect(emissions.single.audioPermissionExplainerRequested, isTrue);
      expect(emissions.single.isDictating, isFalse);
      expect(stt.startedLocaleIds, isEmpty);
      await stt.dispose();
      await bloc.close();
    });

    test('happy path: partial → final commits committedDictationText', () async {
      final permissions = FakePermissionsService()..microphone = PermissionResult.granted;
      final stt = FakeSttService();
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'n1'),
        permissionsService: permissions,
        sttService: stt,
      );

      // Start dictation.
      await _drain(
        bloc,
        () async => bloc.add(const DictationStarted()),
        expectedCount: 1,
      );
      expect(bloc.state.isDictating, isTrue);
      expect(bloc.state.dictationDraft, isEmpty);
      expect(stt.startedLocaleIds, hasLength(1));

      // Partial result flows through the synthetic-event bridge.
      stt.emitPartial('hello');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bloc.state.dictationDraft, 'hello');

      // Final result clears the draft and surfaces the one-shot commit.
      stt.emitFinal('hello world');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(bloc.state.isDictating, isFalse);
      expect(bloc.state.dictationDraft, isNull);
      expect(bloc.state.committedDictationText, 'hello world');
      // Screen owns block-list mutations; the bloc never persists.
      expect(fake.savedNotes, isEmpty);
      await stt.dispose();
      await bloc.close();
    });

    test('DictationCancelled mid-session resets state without committing', () async {
      final permissions = FakePermissionsService()..microphone = PermissionResult.granted;
      final stt = FakeSttService();
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'n1'),
        permissionsService: permissions,
        sttService: stt,
      );

      await _drain(
        bloc,
        () async => bloc.add(const DictationStarted()),
        expectedCount: 1,
      );
      stt.emitPartial('half-formed');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await _drain(
        bloc,
        () async => bloc.add(const DictationCancelled()),
        expectedCount: 1,
      );

      expect(stt.cancelCount, 1);
      expect(bloc.state.isDictating, isFalse);
      expect(bloc.state.dictationDraft, isNull);
      expect(bloc.state.committedDictationText, isNull);
      await stt.dispose();
      await bloc.close();
    });

    test('empty final result does not surface committedDictationText', () async {
      final permissions = FakePermissionsService()..microphone = PermissionResult.granted;
      final stt = FakeSttService();
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'n1'),
        permissionsService: permissions,
        sttService: stt,
      );

      await _drain(
        bloc,
        () async => bloc.add(const DictationStarted()),
        expectedCount: 1,
      );

      // Recognizer emitted a final with no captured speech (e.g. silence
      // timeout). The bloc clears state but does not surface a commit
      // signal — the screen has nothing to append.
      stt.emitFinal('   ');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(bloc.state.isDictating, isFalse);
      expect(bloc.state.committedDictationText, isNull);
      await stt.dispose();
      await bloc.close();
    });

    test('close() cancels in-flight dictation and the recognizer subscription', () async {
      final permissions = FakePermissionsService()..microphone = PermissionResult.granted;
      final stt = FakeSttService();
      final bloc = await _readyBloc(
        fake: fake,
        identityRepository: identityRepository,
        imageService: imageService,
        cancelledNotificationIds: cancelledNotificationIds,
        seed: _buildNote(id: 'n1'),
        permissionsService: permissions,
        sttService: stt,
      );

      await _drain(
        bloc,
        () async => bloc.add(const DictationStarted()),
        expectedCount: 1,
      );
      // FakeSttService flips isListening to true on startDictation.
      expect(stt.isListening, isTrue);

      await bloc.close();

      // close() must call _stt.cancel() while listening (architecture
      // invariant 8).
      expect(stt.cancelCount, greaterThanOrEqualTo(1));
      await stt.dispose();
    });
  });
}
