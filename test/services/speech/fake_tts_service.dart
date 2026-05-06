import 'dart:async';

import 'package:noti_notes_app/services/speech/tts_models.dart';
import 'package:noti_notes_app/services/speech/tts_service.dart';

/// Test double for [TtsService]. Public mutable fields configure scripted
/// behavior; recording lists let tests assert call order without going
/// through the real `flutter_tts` plugin or platform channels.
///
/// Mirrors the shape of [FakeSttService]: scripted return values, recording
/// lists for invocations, and `emit*` helpers for driving the active
/// session's stream from inside a test.
class FakeTtsService implements TtsService {
  /// Voices returned from [availableVoices].
  List<TtsVoice> availableVoicesReturn = const <TtsVoice>[];

  /// Records every text passed to [speak] in the order it was invoked.
  final List<String> speakCalls = [];

  /// Records the `voiceName` argument of every [speak] call (parallel to
  /// [speakCalls]).
  final List<String?> speakVoices = [];

  /// Records every `(rate, pitch)` pair passed to [speak].
  final List<({double rate, double pitch})> speakParams = [];

  /// Recorded `pause()` invocations.
  int pauseCount = 0;

  /// Recorded `stop()` invocations.
  int stopCount = 0;

  StreamController<TtsEvent>? _controller;
  bool _speaking = false;

  @override
  bool get isSpeaking => _speaking;

  @override
  Future<List<TtsVoice>> availableVoices() async => availableVoicesReturn;

  @override
  Stream<TtsEvent> speak(
    String text, {
    String? voiceName,
    double rate = 1.0,
    double pitch = 1.0,
  }) {
    speakCalls.add(text);
    speakVoices.add(voiceName);
    speakParams.add((rate: rate, pitch: pitch));

    final controller = StreamController<TtsEvent>();
    _controller = controller;
    _speaking = true;
    return controller.stream;
  }

  @override
  Future<void> pause() async {
    pauseCount++;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    await _emitCompletion();
  }

  /// Pushes a per-word progress event into the active session. No-op if
  /// no session is active or the controller is closed.
  void emitProgress({
    required String text,
    required int start,
    required int end,
    required String word,
  }) {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.add(
      TtsProgressEvent(
        TtsProgress(text: text, start: start, end: end, word: word),
      ),
    );
  }

  /// Emits the terminal [TtsBlockCompleted] and closes the active stream.
  /// Mirrors the real plugin's terminal-event semantics.
  Future<void> emitBlockCompleted() async {
    await _emitCompletion();
  }

  /// Pushes an error onto the active session and closes the stream — used
  /// to verify the bloc's error-cancellation path.
  Future<void> emitError(Object error) async {
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.addError(error);
    await _emitCompletion();
  }

  Future<void> _emitCompletion() async {
    _speaking = false;
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    controller.add(const TtsBlockCompleted());
    await controller.close();
    _controller = null;
  }

  Future<void> dispose() async {
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _controller = null;
    _speaking = false;
  }
}
