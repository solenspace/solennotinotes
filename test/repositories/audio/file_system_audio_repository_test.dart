import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/repositories/audio/file_system_audio_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Minimal `path_provider` test double: returns the supplied directory for
/// every "documents" lookup; unused lookups throw to flag accidental usage.
class _TempDirPathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _TempDirPathProvider(this.documentsDir);

  final Directory documentsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late FileSystemAudioRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('audio_repo_test_');
    PathProviderPlatform.instance = _TempDirPathProvider(tempDir);
    repo = FileSystemAudioRepository();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FileSystemAudioRepository — file lifecycle', () {
    // Capture + finalize + cancel exercise platform channels in
    // `package:record`, so they are validated by the spec's manual-smoke
    // checklist on iOS sim + Android emulator rather than here. These
    // tests cover the deterministic file-system behavior the repository
    // owns directly.

    test('resolveFile returns the canonical asset path', () async {
      const noteId = 'note-1';
      const audioId = 'asset-1';
      final file = await repo.resolveFile(noteId: noteId, audioId: audioId);
      expect(
        file.path,
        p.join(tempDir.path, 'notes', noteId, 'audio', '$audioId.m4a'),
      );
    });

    test('delete removes the asset on disk', () async {
      const noteId = 'note-1';
      const audioId = 'asset-1';
      final dir = Directory(p.join(tempDir.path, 'notes', noteId, 'audio'));
      dir.createSync(recursive: true);
      final file = File(p.join(dir.path, '$audioId.m4a'));
      file.writeAsBytesSync(<int>[0, 1, 2, 3]);
      expect(file.existsSync(), isTrue);

      await repo.delete(noteId: noteId, audioId: audioId);

      expect(file.existsSync(), isFalse);
    });

    test('delete is a no-op when the asset does not exist', () async {
      // No exception, no error — silent no-op.
      await repo.delete(noteId: 'note-1', audioId: 'missing');
      expect(true, isTrue);
    });

    test('resolveFile creates the per-note audio dir on first lookup', () async {
      const noteId = 'note-2';
      final dir = Directory(p.join(tempDir.path, 'notes', noteId, 'audio'));
      expect(dir.existsSync(), isFalse);
      await repo.resolveFile(noteId: noteId, audioId: 'any');
      expect(dir.existsSync(), isTrue);
    });
  });
}
