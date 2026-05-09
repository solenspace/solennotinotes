import 'dart:async';

import 'package:noti_notes_app/services/ai/whisper_runtime.dart';

/// Test double for [WhisperRuntime]. Mirrors the project's hand-rolled
/// fake pattern (`FakeLlmRuntime`): public mutable fields configure the
/// next call; recording lists / counters capture invocations.
///
/// Each [transcribe] call hands the test a [StreamController] via
/// [emitProgress] / [emitResult] / [emitError] / [completeTranscription];
/// if [scriptedEvents] is set, the controller plays them back
/// automatically (mirrors `FakeLlmRuntime.scriptedTokens`).
class FakeWhisperRuntime implements WhisperRuntime {
  bool _isLoaded = false;

  /// Drives [load] return values. Defaults to true.
  bool loadResult = true;

  /// If set, [load] throws this object once.
  Object? loadThrows;

  /// If set, [transcribe] populates the stream with these events, one
  /// per microtask, then closes. Cleared after each [transcribe] call.
  List<TranscriptionEvent>? scriptedEvents;

  /// If set, [transcribe] adds this error to the stream after
  /// [scriptedEvents] have been emitted. Cleared after each call.
  Object? scriptedError;

  /// Counters.
  int loadCalls = 0;
  int unloadCalls = 0;
  int transcribeCalls = 0;
  String? lastModelPath;
  String? lastAudioFilePath;

  StreamController<TranscriptionEvent>? _activeController;
  bool _activeCancelled = false;

  bool get activeStreamCancelled => _activeCancelled;

  @override
  bool get isLoaded => _isLoaded;

  @override
  Future<bool> load({required String modelPath}) async {
    loadCalls++;
    lastModelPath = modelPath;
    final t = loadThrows;
    if (t != null) {
      loadThrows = null;
      throw t;
    }
    _isLoaded = loadResult;
    return loadResult;
  }

  @override
  Stream<TranscriptionEvent> transcribe({required String audioFilePath}) {
    transcribeCalls++;
    lastAudioFilePath = audioFilePath;
    if (!_isLoaded) {
      return Stream<TranscriptionEvent>.error(StateError('not loaded'));
    }
    _activeCancelled = false;
    final controller = StreamController<TranscriptionEvent>(
      onCancel: () {
        _activeCancelled = true;
      },
    );
    _activeController = controller;
    final events = scriptedEvents;
    final err = scriptedError;
    scriptedEvents = null;
    scriptedError = null;
    if (events != null || err != null) {
      Future<void>(() async {
        if (events != null) {
          for (final e in events) {
            if (controller.isClosed) return;
            controller.add(e);
            await Future<void>.delayed(Duration.zero);
          }
        }
        if (err != null && !controller.isClosed) {
          controller.addError(err);
        }
        if (!controller.isClosed) await controller.close();
      });
    }
    return controller.stream;
  }

  @override
  Future<void> unload() async {
    unloadCalls++;
    final c = _activeController;
    if (c != null && !c.isClosed) await c.close();
    _activeController = null;
    _isLoaded = false;
  }

  /// Manually push a progress event to the active transcription.
  void emitProgress(double fraction) {
    final c = _activeController;
    if (c == null || c.isClosed) return;
    c.add(TranscriptionProgress(fraction));
  }

  /// Manually push a result event to the active transcription. Does
  /// not close the stream — call [completeTranscription] when ready.
  void emitResult(String text) {
    final c = _activeController;
    if (c == null || c.isClosed) return;
    c.add(TranscriptionResult(text));
  }

  /// Cleanly close the active transcription stream.
  Future<void> completeTranscription() async {
    final c = _activeController;
    if (c == null || c.isClosed) return;
    await c.close();
  }

  /// Push an error onto the active transcription stream.
  void emitError(Object error) {
    final c = _activeController;
    if (c == null || c.isClosed) return;
    c.addError(error);
  }

  Future<void> dispose() async {
    final c = _activeController;
    if (c != null && !c.isClosed) await c.close();
    _activeController = null;
  }
}
