import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/repositories/notes/hive_notes_repository.dart';
import 'package:noti_notes_app/services/image/image_picker_service.dart';

/// Records every removeImage call so tests can assert on-disk cleanup
/// without touching the real filesystem outside the temp dir.
class _RecordingImageService implements ImagePickerService {
  final List<File> removed = [];

  @override
  Future<File?> pickImage(_, __) async => null;

  @override
  Future<void> removeImage(File image) async {
    removed.add(image);
  }
}

Note _buildNote({
  required String id,
  String title = 'title',
  String content = 'content',
  Set<String>? tags,
  DateTime? dateCreated,
  DateTime? reminder,
  File? imageFile,
  bool hasGradient = false,
  LinearGradient? gradient,
  bool isPinned = false,
  int? sortIndex,
  List<Map<String, dynamic>>? blocks,
  List<Map<String, dynamic>>? todoList,
}) {
  return Note(
    tags ?? const {'work'},
    imageFile,
    null, // patternImage
    todoList ?? const [],
    reminder,
    gradient,
    id: id,
    title: title,
    content: content,
    dateCreated: dateCreated ?? DateTime(2026, 5, 4, 12),
    colorBackground: const Color(0xFFEDE6D6),
    fontColor: const Color(0xFF1C1B1A),
    hasGradient: hasGradient,
    isPinned: isPinned,
    sortIndex: sortIndex,
    blocks: blocks,
  );
}

void main() {
  late Directory tempDir;
  late Box<dynamic> box;
  late _RecordingImageService imageService;
  late HiveNotesRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_notes_repo_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>('notes_v2');
    imageService = _RecordingImageService();
    repo = HiveNotesRepository.withBox(box: box, imageService: imageService);
  });

  tearDown(() async {
    await box.close();
    await Hive.deleteBoxFromDisk('notes_v2');
    await tempDir.delete(recursive: true);
  });

  group('HiveNotesRepository', () {
    test('init is idempotent when the box is already open', () async {
      await repo.init();
      await repo.init();
      expect(box.isOpen, isTrue);
    });

    test('save then getAll round-trips a simple note', () async {
      final note = _buildNote(id: 'n1', title: 'hello');
      await repo.save(note);

      final fetched = await repo.getAll();
      expect(fetched, hasLength(1));
      expect(fetched.first.id, 'n1');
      expect(fetched.first.title, 'hello');
    });

    test('save with empty id is a no-op', () async {
      await repo.save(_buildNote(id: ''));
      expect(box.length, 0);
    });

    test('saveAll persists every note', () async {
      await repo.saveAll([
        _buildNote(id: 'a'),
        _buildNote(id: 'b'),
        _buildNote(id: 'c'),
      ]);
      final all = await repo.getAll();
      expect(all.map((n) => n.id).toSet(), {'a', 'b', 'c'});
    });

    test('watchAll emits the initial snapshot then re-emits on save', () async {
      await repo.save(_buildNote(id: 'first'));

      // take(2) auto-closes the stream after two events so the async-generator
      // cleanup races aren't a factor.
      final future = expectLater(
        repo.watchAll().take(2),
        emitsInOrder([
          predicate<List<Note>>(
            (notes) => notes.length == 1 && notes.first.id == 'first',
            'snapshot with only "first"',
          ),
          predicate<List<Note>>(
            (notes) => notes.map((n) => n.id).toSet().containsAll({'first', 'second'}),
            'snapshot containing "first" and "second"',
          ),
        ]),
      );

      // Allow the subscription to register before triggering the second event.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.save(_buildNote(id: 'second'));

      await future;
    });

    test('delete removes the entry and walks the image service for image notes', () async {
      final imageFile = File('${tempDir.path}/dummy.png');
      await imageFile.writeAsBytes([1, 2, 3]);

      await repo.save(_buildNote(id: 'with-image', imageFile: imageFile));
      await repo.save(_buildNote(id: 'no-image'));

      await repo.delete('with-image');
      expect(box.containsKey('with-image'), isFalse);
      expect(imageService.removed, hasLength(1));
      expect(imageService.removed.first.path, imageFile.path);

      await repo.delete('no-image');
      expect(box.containsKey('no-image'), isFalse);
      expect(imageService.removed, hasLength(1)); // no extra removal call
    });

    test('delete on missing id is a no-op', () async {
      await repo.delete('does-not-exist');
      expect(imageService.removed, isEmpty);
    });

    test('clear walks every image and empties the box', () async {
      final image1 = File('${tempDir.path}/a.png');
      final image2 = File('${tempDir.path}/b.png');
      await image1.writeAsBytes([1]);
      await image2.writeAsBytes([2]);

      await repo.save(_buildNote(id: 'a', imageFile: image1));
      await repo.save(_buildNote(id: 'b', imageFile: image2));
      await repo.save(_buildNote(id: 'c'));

      await repo.clear();
      expect(box.length, 0);
      expect(imageService.removed.map((f) => f.path).toSet(), {image1.path, image2.path});
    });

    test('Note.fromJson(jsonDecode(toJson)) round-trips every field', () async {
      final note = _buildNote(
        id: 'full',
        title: 'Full',
        content: 'Body',
        tags: {'a', 'b'},
        dateCreated: DateTime(2026, 5, 4, 14, 30),
        reminder: DateTime(2026, 5, 5, 9),
        hasGradient: true,
        gradient: const LinearGradient(
          colors: [Color(0xFF112233), Color(0xFF445566)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        isPinned: true,
        sortIndex: 7,
        blocks: const [
          {'type': 'text', 'id': 'b1', 'text': 'hello'},
          {'type': 'checklist', 'id': 'b2', 'isChecked': false, 'text': 'todo'},
        ],
        todoList: const [
          {'content': 'milk', 'isChecked': false},
        ],
      );

      await repo.save(note);
      final fetched = (await repo.getAll()).single;

      expect(fetched.id, note.id);
      expect(fetched.title, note.title);
      expect(fetched.content, note.content);
      expect(fetched.tags, note.tags);
      expect(fetched.dateCreated, note.dateCreated);
      expect(fetched.reminder, note.reminder);
      expect(fetched.hasGradient, true);
      expect(fetched.gradient, isNotNull);
      expect(
        fetched.gradient!.colors.map((c) => c.toARGB32()),
        note.gradient!.colors.map((c) => c.toARGB32()),
      );
      expect(fetched.gradient!.begin, Alignment.topLeft);
      expect(fetched.gradient!.end, Alignment.bottomRight);
      expect(fetched.isPinned, true);
      expect(fetched.sortIndex, 7);
      expect(fetched.blocks, hasLength(2));
      expect(fetched.blocks.first['type'], 'text');
      expect(fetched.todoList.first['content'], 'milk');
    });

    test('Note.fromJson handles null reminder and absent gradient as legacy did', () async {
      // Simulate a v2 row written with the legacy semantics:
      // reminder='' empty string, gradient='' empty string.
      final json = <String, dynamic>{
        'id': 'legacy',
        'title': 'L',
        'content': '',
        'tags': <String>[],
        'dateCreated': DateTime(2026, 5, 4).toIso8601String(),
        'reminder': '',
        'colorBackground': const Color(0xFFEDE6D6).toARGB32(),
        'fontColor': const Color(0xFF1C1B1A).toARGB32(),
        'imageFile': null,
        'patternImage': null,
        'todoList': <Map<String, dynamic>>[],
        'displayMode': DisplayMode.normal.index,
        'hasGradient': false,
        'gradient': '',
        'isPinned': false,
        'sortIndex': null,
        'blocks': <Map<String, dynamic>>[],
      };
      await box.put('legacy', jsonEncode(json));

      final fetched = (await repo.getAll()).single;
      expect(fetched.reminder, isNull);
      expect(fetched.gradient, isNull);
      expect(fetched.imageFile, isNull);
    });
  });
}
