import 'dart:async';
import 'dart:io';

import 'package:noti_notes_app/services/ai/llm_model_downloader.dart';

/// Test double for [LlmModelDownloader]. Mirrors the project's hand-rolled
/// fake pattern (`FakeSttService`, `FakeAudioRepository`): public mutable
/// fields configure the next call, recording lists capture invocations.
///
/// The real downloader's `download()` opens an `HttpClient`; tests here
/// drive a `StreamController<DownloadProgress>` directly so no network /
/// filesystem ever participates.
class FakeLlmModelDownloader implements LlmModelDownloader {
  /// Flips the next [isAlreadyDownloaded] result. Default `false` so the
  /// cubit's `bootstrap()` leaves the row in `idle` and tests opt-in.
  bool alreadyDownloaded = false;

  /// Recorded `deletePartial()` calls.
  int deletePartialCount = 0;

  /// Recorded `deleteAll()` calls.
  int deleteAllCount = 0;

  /// Returned by [resolveTargetFile]. Default points at a non-existent
  /// path so tests that touch the file have to opt in.
  File targetFile = File('/tmp/fake-llm-model.gguf');

  StreamController<DownloadProgress>? _controller;

  @override
  Future<File> resolveTargetFile() async => targetFile;

  @override
  Future<bool> isAlreadyDownloaded() async => alreadyDownloaded;

  @override
  Stream<DownloadProgress> download() {
    final controller = StreamController<DownloadProgress>();
    _controller = controller;
    return controller.stream;
  }

  @override
  Future<void> deletePartial() async {
    deletePartialCount++;
  }

  @override
  Future<void> deleteAll() async {
    deleteAllCount++;
  }

  void emitDownloading(int bytes, int total) {
    final c = _controller;
    if (c == null || c.isClosed) return;
    c.add(DownloadProgress.downloading(bytes, total));
  }

  void emitVerifying() {
    final c = _controller;
    if (c == null || c.isClosed) return;
    c.add(const DownloadProgress.verifying());
  }

  void emitReady() {
    final c = _controller;
    if (c == null || c.isClosed) return;
    c.add(const DownloadProgress.ready());
    c.close();
    _controller = null;
  }

  void emitFailed(String reason) {
    final c = _controller;
    if (c == null || c.isClosed) return;
    c.add(DownloadProgress.failed(reason));
    c.close();
    _controller = null;
  }

  void emitError(Object error) {
    final c = _controller;
    if (c == null || c.isClosed) return;
    c.addError(error);
    c.close();
    _controller = null;
  }

  /// Cleanly tears down any open controller. Tests should call this in
  /// `tearDown` so unclosed streams do not leak between tests.
  Future<void> dispose() async {
    final c = _controller;
    if (c != null && !c.isClosed) {
      await c.close();
    }
    _controller = null;
  }
}
