import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/services/ai/llm_model_constants.dart';
import 'package:noti_notes_app/services/ai/model_download_spec.dart';
import 'package:noti_notes_app/services/ai/model_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// In-memory `path_provider` substitute used by the existing repository
/// tests; reused here so the downloader can resolve `<app_support>/<sub>/`
/// against a temporary directory under the host OS, not the real device's
/// support dir. Mirrors the shape of
/// `test/repositories/audio/file_system_audio_repository_test.dart`.
class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this._supportDir);
  final Directory _supportDir;

  @override
  Future<String?> getApplicationSupportPath() async => _supportDir.path;
}

/// A second spec under a different subdirectory, used to verify the
/// downloader can serve coexisting model families (LLM + Whisper) from a
/// single instance without partial-file cross-contamination.
const _whisperLikeSpec = ModelDownloadSpec(
  subdirectory: 'whisper',
  filename: 'fake-whisper-test.bin',
  url: 'https://example.invalid/fake-whisper.bin',
  sha256: '0000000000000000000000000000000000000000000000000000000000000000',
  totalBytes: 0,
  version: '0.0.0-test',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late ModelDownloader downloader;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('model_downloader_test_');
    PathProviderPlatform.instance = _FakePathProvider(tempRoot);
    downloader = const ModelDownloader();
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('ModelDownloader.resolveTargetFile', () {
    test('returns <app_support>/<subdirectory>/<filename> and creates the dir', () async {
      final file = await downloader.resolveTargetFile(LlmModelConstants.spec);
      expect(
        file.path,
        equals(p.join(tempRoot.path, 'llm', LlmModelConstants.filename)),
      );
      expect(Directory(p.join(tempRoot.path, 'llm')).existsSync(), isTrue);
    });

    test('honours per-spec subdirectory (LLM and Whisper coexist)', () async {
      final llmFile = await downloader.resolveTargetFile(LlmModelConstants.spec);
      final whisperFile = await downloader.resolveTargetFile(_whisperLikeSpec);

      expect(p.dirname(llmFile.path), equals(p.join(tempRoot.path, 'llm')));
      expect(p.dirname(whisperFile.path), equals(p.join(tempRoot.path, 'whisper')));
      expect(p.basename(whisperFile.path), equals('fake-whisper-test.bin'));
    });

    test('is idempotent on the directory creation', () async {
      await downloader.resolveTargetFile(LlmModelConstants.spec);
      await downloader.resolveTargetFile(LlmModelConstants.spec);
      // Second call must not throw a "directory exists" error.
      expect(
        Directory(p.join(tempRoot.path, 'llm')).existsSync(),
        isTrue,
      );
    });
  });

  group('ModelDownloader.isAlreadyDownloaded', () {
    test('returns false when no file is present', () async {
      expect(await downloader.isAlreadyDownloaded(LlmModelConstants.spec), isFalse);
    });

    test('returns false when the file exists but the digest does not match', () async {
      final target = await downloader.resolveTargetFile(LlmModelConstants.spec);
      await target.writeAsBytes(List<int>.filled(64, 0));
      expect(await downloader.isAlreadyDownloaded(LlmModelConstants.spec), isFalse);
    });
  });

  group('ModelDownloader.deletePartial', () {
    test('removes <target>.partial when present', () async {
      final target = await downloader.resolveTargetFile(LlmModelConstants.spec);
      final partial = File('${target.path}.partial');
      await partial.writeAsBytes([1, 2, 3]);
      expect(partial.existsSync(), isTrue);
      await downloader.deletePartial(LlmModelConstants.spec);
      expect(partial.existsSync(), isFalse);
    });

    test('only deletes the partial for the given spec (no cross-contamination)', () async {
      final llmTarget = await downloader.resolveTargetFile(LlmModelConstants.spec);
      final whisperTarget = await downloader.resolveTargetFile(_whisperLikeSpec);
      final llmPartial = File('${llmTarget.path}.partial');
      final whisperPartial = File('${whisperTarget.path}.partial');
      await llmPartial.writeAsBytes([1]);
      await whisperPartial.writeAsBytes([2]);

      await downloader.deletePartial(LlmModelConstants.spec);

      expect(llmPartial.existsSync(), isFalse);
      expect(whisperPartial.existsSync(), isTrue);
    });

    test('is a no-op when no partial exists', () async {
      // Just verify it doesn't throw.
      await downloader.deletePartial(LlmModelConstants.spec);
    });
  });

  group('ModelDownloader.deleteAll', () {
    test('removes both target and partial when present', () async {
      final target = await downloader.resolveTargetFile(LlmModelConstants.spec);
      final partial = File('${target.path}.partial');
      await target.writeAsBytes([0]);
      await partial.writeAsBytes([1]);
      await downloader.deleteAll(LlmModelConstants.spec);
      expect(target.existsSync(), isFalse);
      expect(partial.existsSync(), isFalse);
    });

    test('deletes only the spec-targeted file (Whisper file untouched)', () async {
      final llmTarget = await downloader.resolveTargetFile(LlmModelConstants.spec);
      final whisperTarget = await downloader.resolveTargetFile(_whisperLikeSpec);
      await llmTarget.writeAsBytes([0]);
      await whisperTarget.writeAsBytes([0]);

      await downloader.deleteAll(LlmModelConstants.spec);

      expect(llmTarget.existsSync(), isFalse);
      expect(whisperTarget.existsSync(), isTrue);
    });
  });
}
