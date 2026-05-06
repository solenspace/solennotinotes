import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'package:noti_notes_app/services/speech/tts_models.dart';

/// Wrapper around `package:flutter_tts` that exposes a sealed [TtsEvent]
/// stream rather than the plugin's loose handler callbacks. Per
/// code-standards "Forbidden imports (hygiene)", this is the only library
/// under `lib/` allowed to import `package:flutter_tts`.
///
/// The plugin maps to native engines: iOS `AVSpeechSynthesizer` and
/// Android `TextToSpeech`. Both ship with bundled voices and run fully
/// offline — no transitive network dependency, satisfying invariant 1.
abstract class TtsService {
  /// Voices the OS reports as installed. Empty list on platforms or
  /// engines that do not surface the list.
  Future<List<TtsVoice>> availableVoices();

  /// Speaks [text]. Returns a stream that emits a [TtsProgressEvent] per
  /// word and exactly one terminal [TtsBlockCompleted] when the synthesizer
  /// finishes the utterance, when [stop] is called, or when an error path
  /// short-circuits the session. The stream closes after the terminal
  /// event.
  ///
  /// `voiceName` is matched against [availableVoices]; an unknown name
  /// silently falls back to the OS default. `rate` and `pitch` follow the
  /// plugin's bounds (rate `[0.1, 2.0]`, pitch `[0.5, 2.0]`); values
  /// outside those bounds are clamped.
  Stream<TtsEvent> speak(
    String text, {
    String? voiceName,
    double rate = 1.0,
    double pitch = 1.0,
  });

  /// Pauses the active session. iOS resumes mid-utterance on the next
  /// [speak] call; Android's plugin maps `pause()` to `stop()` (no native
  /// resume primitive) so the next [speak] restarts from the start of the
  /// supplied text. See progress-tracker open question 20.
  Future<void> pause();

  /// Stops the active session and emits the terminal [TtsBlockCompleted]
  /// before the stream closes. Safe to call from `Bloc.close()`
  /// (architecture invariant 8).
  Future<void> stop();

  bool get isSpeaking;
}

class PluginTtsService implements TtsService {
  PluginTtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  StreamController<TtsEvent>? _controller;
  bool _handlersWired = false;
  bool _speaking = false;

  @override
  bool get isSpeaking => _speaking;

  @override
  Future<List<TtsVoice>> availableVoices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const <TtsVoice>[];
    return raw
        .whereType<Map>()
        .map(
          (m) => TtsVoice(
            name: (m['name'] ?? '').toString(),
            locale: (m['locale'] ?? '').toString(),
          ),
        )
        .where((v) => v.name.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Stream<TtsEvent> speak(
    String text, {
    String? voiceName,
    double rate = 1.0,
    double pitch = 1.0,
  }) {
    final controller = StreamController<TtsEvent>();
    _controller = controller;
    _speaking = true;
    unawaited(_runSession(controller, text, voiceName, rate, pitch));
    return controller.stream;
  }

  Future<void> _runSession(
    StreamController<TtsEvent> controller,
    String text,
    String? voiceName,
    double rate,
    double pitch,
  ) async {
    _wireHandlersOnce();
    try {
      // flutter_tts requires {name, locale} together. Look up the locale
      // from availableVoices once at speak-start; on miss, leave the
      // engine on its default voice.
      if (voiceName != null && voiceName.isNotEmpty) {
        final voices = await availableVoices();
        final match = voices.where((v) => v.name == voiceName).firstOrNull;
        if (match != null) {
          await _tts.setVoice({'name': match.name, 'locale': match.locale});
        }
      }
      await _tts.setSpeechRate(rate.clamp(0.1, 2.0));
      await _tts.setPitch(pitch.clamp(0.5, 2.0));
      await _tts.speak(text);
    } on Object catch (e) {
      if (!controller.isClosed) {
        controller.addError(e);
        await _emitCompletion(controller);
      }
    }
  }

  void _wireHandlersOnce() {
    if (_handlersWired) return;
    _handlersWired = true;

    _tts.setProgressHandler((text, start, end, word) {
      final controller = _controller;
      if (controller == null || controller.isClosed) return;
      controller.add(
        TtsProgressEvent(
          TtsProgress(text: text, start: start, end: end, word: word),
        ),
      );
    });
    _tts.setCompletionHandler(() {
      _emitCompletion(_controller);
    });
    _tts.setCancelHandler(() {
      _emitCompletion(_controller);
    });
    _tts.setErrorHandler((Object? msg) {
      final controller = _controller;
      if (controller == null || controller.isClosed) return;
      controller.addError(StateError('flutter_tts error: $msg'));
      _emitCompletion(controller);
    });
  }

  Future<void> _emitCompletion(StreamController<TtsEvent>? controller) async {
    _speaking = false;
    if (controller == null || controller.isClosed) return;
    controller.add(const TtsBlockCompleted());
    await controller.close();
    if (identical(_controller, controller)) {
      _controller = null;
    }
  }

  @override
  Future<void> pause() async {
    await _tts.pause();
  }

  @override
  Future<void> stop() async {
    _speaking = false;
    await _tts.stop();
    await _emitCompletion(_controller);
  }
}
