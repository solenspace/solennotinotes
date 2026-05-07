import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/services/ai/llm_model_constants.dart';
import 'package:noti_notes_app/services/ai/llm_model_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// In-memory `path_provider` substitute used by the existing repository
/// tests; reused here so the downloader can resolve `<app_support>/llm/`
/// against a temporary directory under the host OS, not the real device's
/// support dir. Mirrors the shape of
/// `test/repositories/audio/file_system_audio_repository_test.dart`.
class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this._supportDir);
  final Directory _supportDir;

  @override
  Future<String?> getApplicationSupportPath() async => _supportDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late LlmModelDownloader downloader;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('llm_downloader_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot);
    downloader = const LlmModelDownloader();
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('LlmModelDownloader.resolveTargetFile', () {
    test('returns <app_support>/llm/<filename> and creates the dir', () async {
      final file = await downloader.resolveTargetFile();
      expect(
        file.path,
        equals(p.join(tempRoot.path, 'llm', LlmModelConstants.filename)),
      );
      expect(Directory(p.join(tempRoot.path, 'llm')).existsSync(), isTrue);
    });

    test('is idempotent on the directory creation', () async {
      await downloader.resolveTargetFile();
      await downloader.resolveTargetFile();
      // Second call must not throw a "directory exists" error.
      expect(
        Directory(p.join(tempRoot.path, 'llm')).existsSync(),
        isTrue,
      );
    });
  });

  group('LlmModelDownloader.isAlreadyDownloaded', () {
    test('returns false when no file is present', () async {
      expect(await downloader.isAlreadyDownloaded(), isFalse);
    });

    test('returns false when the file exists but the digest does not match', () async {
      final target = await downloader.resolveTargetFile();
      await target.writeAsBytes(List<int>.filled(64, 0));
      expect(await downloader.isAlreadyDownloaded(), isFalse);
    });
  });

  group('LlmModelDownloader.deletePartial', () {
    test('removes <target>.partial when present', () async {
      final target = await downloader.resolveTargetFile();
      final partial = File('${target.path}.partial');
      await partial.writeAsBytes([1, 2, 3]);
      expect(partial.existsSync(), isTrue);
      await downloader.deletePartial();
      expect(partial.existsSync(), isFalse);
    });

    test('is a no-op when no partial exists', () async {
      // Just verify it doesn't throw.
      await downloader.deletePartial();
    });
  });

  group('LlmModelDownloader.deleteAll', () {
    test('removes both target and partial when present', () async {
      final target = await downloader.resolveTargetFile();
      final partial = File('${target.path}.partial');
      await target.writeAsBytes([0]);
      await partial.writeAsBytes([1]);
      await downloader.deleteAll();
      expect(target.existsSync(), isFalse);
      expect(partial.existsSync(), isFalse);
    });
  });
}
