import 'dart:async';
import 'dart:io';

import 'package:noti_notes_app/services/ai/model_download_spec.dart';
import 'package:noti_notes_app/services/ai/model_downloader.dart';

/// Test double for [ModelDownloader]. Mirrors the project's hand-rolled
/// fake pattern (`FakeSttService`, `FakeAudioRepository`): public mutable
/// fields configure the next call, recording lists capture invocations.
///
/// The real downloader's `download()` opens an `HttpClient`; tests here
/// drive a `StreamController<DownloadProgress>` directly so no network /
/// filesystem ever participates.
///
/// One fake instance can serve multiple specs (e.g. LLM + Whisper) so a
/// single test can drive both readiness cubits side-by-side. Per-spec
/// behaviour is keyed by [ModelDownloadSpec.subdirectory] (lookup order:
/// per-key map → fall-through to the top-level public fields, which
/// remain backwards-compatible with single-spec tests).
class FakeModelDownloader implements ModelDownloader {
  /// Flips the next [isAlreadyDownloaded] result. Default `false` so the
  /// cubit's `bootstrap()` leaves the row in `idle` and tests opt-in.
  bool alreadyDownloaded = false;

  /// Per-subdirectory override of [alreadyDownloaded]. When set, takes
  /// precedence over the shared field. Lets a multi-cubit test report
  /// "LLM is ready, Whisper is not" without two fake instances.
  final Map<String, bool> alreadyDownloadedBySubdir = {};

  /// Recorded `deletePartial()` calls (any spec).
  int deletePartialCount = 0;

  /// Per-subdirectory recorded `deletePartial()` count.
  final Map<String, int> deletePartialCountBySubdir = {};

  /// Recorded `deleteAll()` calls (any spec).
  int deleteAllCount = 0;

  /// Per-subdirectory recorded `deleteAll()` count.
  final Map<String, int> deleteAllCountBySubdir = {};

  /// Returned by [resolveTargetFile]. Default points at a non-existent
  /// path so tests that touch the file have to opt in.
  File targetFile = File('/tmp/fake-model.bin');

  /// Per-subdirectory override of [targetFile].
  final Map<String, File> targetFileBySubdir = {};

  /// The active controller, regardless of which spec opened it. Tests
  /// that drive a single download at a time use this directly via the
  /// `emit*` helpers.
  StreamController<DownloadProgress>? _controller;

  /// Per-subdirectory active controllers, keyed by `spec.subdirectory`.
  /// Allows two concurrent downloads (LLM + Whisper) to be controlled
  /// independently in coexistence tests.
  final Map<String, StreamController<DownloadProgress>> _controllersBySubdir = {};

  @override
  Future<File> resolveTargetFile(ModelDownloadSpec spec) async =>
      targetFileBySubdir[spec.subdirectory] ?? targetFile;

  @override
  Future<bool> isAlreadyDownloaded(ModelDownloadSpec spec) async =>
      alreadyDownloadedBySubdir[spec.subdirectory] ?? alreadyDownloaded;

  @override
  Stream<DownloadProgress> download(ModelDownloadSpec spec) {
    final controller = StreamController<DownloadProgress>();
    _controller = controller;
    _controllersBySubdir[spec.subdirectory] = controller;
    return controller.stream;
  }

  @override
  Future<void> deletePartial(ModelDownloadSpec spec) async {
    deletePartialCount++;
    deletePartialCountBySubdir.update(
      spec.subdirectory,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
  }

  @override
  Future<void> deleteAll(ModelDownloadSpec spec) async {
    deleteAllCount++;
    deleteAllCountBySubdir.update(
      spec.subdirectory,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
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
    _forgetController(c);
  }

  void emitFailed(String reason) {
    final c = _controller;
    if (c == null || c.isClosed) return;
    c.add(DownloadProgress.failed(reason));
    c.close();
    _forgetController(c);
  }

  void emitError(Object error) {
    final c = _controller;
    if (c == null || c.isClosed) return;
    c.addError(error);
    c.close();
    _forgetController(c);
  }

  /// Spec-targeted variants for coexistence tests.
  void emitDownloadingFor(String subdirectory, int bytes, int total) {
    final c = _controllersBySubdir[subdirectory];
    if (c == null || c.isClosed) return;
    c.add(DownloadProgress.downloading(bytes, total));
  }

  void emitReadyFor(String subdirectory) {
    final c = _controllersBySubdir[subdirectory];
    if (c == null || c.isClosed) return;
    c.add(const DownloadProgress.ready());
    c.close();
    _controllersBySubdir.remove(subdirectory);
    if (identical(_controller, c)) _controller = null;
  }

  void _forgetController(StreamController<DownloadProgress> c) {
    _controller = null;
    _controllersBySubdir.removeWhere((_, v) => identical(v, c));
  }

  /// Cleanly tears down any open controller. Tests should call this in
  /// `tearDown` so unclosed streams do not leak between tests.
  Future<void> dispose() async {
    final c = _controller;
    if (c != null && !c.isClosed) {
      await c.close();
    }
    _controller = null;
    for (final ctrl in _controllersBySubdir.values) {
      if (!ctrl.isClosed) await ctrl.close();
    }
    _controllersBySubdir.clear();
  }
}
