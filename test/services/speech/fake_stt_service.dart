import 'dart:async';

import 'package:noti_notes_app/services/speech/stt_models.dart';
import 'package:noti_notes_app/services/speech/stt_service.dart';

/// Test double for [SttService]. Public mutable fields configure the next
/// invocation; recording lists let tests assert call order without going
/// through the real `speech_to_text` plugin or platform channels.
///
/// Mirrors the shape of `FakeAudioRepository` and `FakePermissionsService`:
/// fields default to a deny-by-default so each test opts into success.
class FakeSttService implements SttService {
  FakeSttService({this.offlineCapable = true});

  /// Whether [isOfflineCapable] reports `true`. Default `true` so non-STT
  /// tests inheriting the default fake never hit the offline-incapable
  /// short-circuit.
  bool offlineCapable;

  /// Counts every [startDictation] call so tests can assert it was (or was
  /// not) invoked.
  final List<String?> startedLocaleIds = [];

  /// Recorded `stop()` invocations.
  int stopCount = 0;

  /// Recorded `cancel()` invocations.
  int cancelCount = 0;

  /// Locales returned by [availableLocales].
  List<SttLocale> availableLocalesReturn = const <SttLocale>[];

  /// True while [_controller] is open (i.e. between [startDictation] and
  /// the next [stop] / [cancel] / final result).
  bool _listening = false;
  StreamController<SttRecognitionEvent>? _controller;

  @override
  bool get isOfflineCapable => offlineCapable;

  @override
  bool get isListening => _listening;

  @override
  Future<List<SttLocale>> availableLocales() async => availableLocalesReturn;

  @override
  Stream<SttRecognitionEvent> startDictation({String? localeId}) {
    startedLocaleIds.add(localeId);
    final controller = StreamController<SttRecognitionEvent>.broadcast();
    _controller = controller;
    _listening = true;
    if (!offlineCapable) {
      controller.add(const SttFinalResult(text: '', confidence: 0));
      controller.close();
      _listening = false;
      return controller.stream;
    }
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _listening = false;
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _controller = null;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
    _listening = false;
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _controller = null;
  }

  /// Pushes a partial recognition result into the active session. No-op if
  /// no session is active or the controller has been closed.
  void emitPartial(String text, {double confidence = 0.5}) {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.add(SttPartialResult(text: text, confidence: confidence));
  }

  /// Pushes a final recognition result into the active session and closes
  /// the stream. Mirrors the real plugin's terminal-event semantics.
  void emitFinal(String text, {double confidence = 0.95}) {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.add(SttFinalResult(text: text, confidence: confidence));
    _listening = false;
    controller.close();
    _controller = null;
  }

  /// Closes the controller without emitting an event — simulates a
  /// recognizer error path.
  void emitError(Object error) {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.addError(error);
    _listening = false;
    controller.close();
    _controller = null;
  }

  Future<void> dispose() async {
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _controller = null;
    _listening = false;
  }
}
