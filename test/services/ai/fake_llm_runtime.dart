import 'dart:async';

import 'package:noti_notes_app/services/ai/llm_runtime.dart';

/// Test double for [LlmRuntime]. Mirrors the project's hand-rolled fake
/// pattern: public mutable fields configure the next call; recording
/// lists / counters capture invocations.
///
/// Each [generate] call hands the test a [StreamController] via
/// [emitToken], [completeGeneration], [errorGeneration]; if [scriptedTokens]
/// is set, the controller plays them back automatically.
class FakeLlmRuntime implements LlmRuntime {
  bool _isLoaded = false;

  /// Drives [load] return values. Defaults to true.
  bool loadResult = true;

  /// If set, [load] throws this object once.
  Object? loadThrows;

  /// If set, [generate] populates the stream with these tokens, one per
  /// microtask, then closes. Cleared after each [generate] call.
  List<String>? scriptedTokens;

  /// If set, [generate] adds this error to the stream after [scriptedTokens]
  /// have been emitted. Cleared after each [generate] call.
  Object? scriptedError;

  /// Number of [load] / [unload] calls so far.
  int loadCalls = 0;
  int unloadCalls = 0;
  int generateCalls = 0;
  String? lastModelPath;
  String? lastPrompt;

  StreamController<String>? _activeController;
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
  Stream<String> generate({
    required String prompt,
    int maxTokens = 256,
    double temperature = 0.7,
  }) {
    generateCalls++;
    lastPrompt = prompt;
    if (!_isLoaded) {
      return Stream<String>.error(StateError('not loaded'));
    }
    _activeCancelled = false;
    final controller = StreamController<String>(
      onCancel: () {
        _activeCancelled = true;
      },
    );
    _activeController = controller;
    final tokens = scriptedTokens;
    final err = scriptedError;
    scriptedTokens = null;
    scriptedError = null;
    if (tokens != null || err != null) {
      Future<void>(() async {
        if (tokens != null) {
          for (final t in tokens) {
            if (controller.isClosed) return;
            controller.add(t);
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

  /// Manually push a token to the active generation. Use when
  /// [scriptedTokens] doesn't fit the test's pacing.
  void emitToken(String text) {
    final c = _activeController;
    if (c == null || c.isClosed) return;
    c.add(text);
  }

  /// Cleanly close the active generation stream as if generation
  /// finished naturally.
  Future<void> completeGeneration() async {
    final c = _activeController;
    if (c == null || c.isClosed) return;
    await c.close();
  }

  /// Push an error onto the active generation stream.
  void errorGeneration(Object error) {
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
