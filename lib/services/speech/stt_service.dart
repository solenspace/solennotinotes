import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:noti_notes_app/services/speech/stt_models.dart';

/// Wrapper around `package:speech_to_text` that hard-gates on offline
/// capability and exposes a sealed [SttRecognitionEvent] stream rather than
/// the plugin's loose result callback. Per code-standards "Forbidden imports
/// (hygiene)", this is the only library under `lib/` allowed to import
/// `package:speech_to_text`.
abstract class SttService {
  /// Whether this device can run STT fully offline. Cached at construction
  /// from [SettingsRepository.getSttOfflineCapable]; the [SttCapabilityProbe]
  /// runs once on cold start in `main()` and persists the result.
  bool get isOfflineCapable;

  /// Locales the OS reports as installed offline. Empty list if the recognizer
  /// is not initialized or the device is not offline-capable.
  Future<List<SttLocale>> availableLocales();

  /// Starts a streaming dictation session. Yields zero or more
  /// [SttPartialResult]s and exactly one [SttFinalResult] when the utterance
  /// ends or [stop] is called. The stream closes after the final event.
  ///
  /// On an offline-incapable device the stream emits a single empty
  /// [SttFinalResult] and closes — defence-in-depth; the bloc should have
  /// already short-circuited via [isOfflineCapable].
  Stream<SttRecognitionEvent> startDictation({String? localeId});

  /// Stops the active session. The recognizer emits one trailing final
  /// result before the stream closes.
  Future<void> stop();

  /// Cancels the active session and discards any pending final result.
  /// Safe to call from `Bloc.close()` (architecture invariant 8).
  Future<void> cancel();

  bool get isListening;
}

class PluginSttService implements SttService {
  PluginSttService({required bool isOfflineCapable, stt.SpeechToText? speech})
      : _offlineCapable = isOfflineCapable,
        _speech = speech ?? stt.SpeechToText();

  final bool _offlineCapable;
  final stt.SpeechToText _speech;

  StreamController<SttRecognitionEvent>? _controller;
  bool _initialized = false;

  @override
  bool get isOfflineCapable => _offlineCapable;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<List<SttLocale>> availableLocales() async {
    if (!_offlineCapable) return const <SttLocale>[];
    if (!await _ensureInit()) return const <SttLocale>[];
    final native = await _speech.locales();
    return native.map((l) => SttLocale(localeId: l.localeId, name: l.name)).toList(growable: false);
  }

  @override
  Stream<SttRecognitionEvent> startDictation({String? localeId}) {
    final controller = StreamController<SttRecognitionEvent>();
    _controller = controller;

    if (!_offlineCapable) {
      controller.add(const SttFinalResult(text: '', confidence: 0));
      controller.close();
      return controller.stream;
    }

    unawaited(_runSession(controller, localeId));
    return controller.stream;
  }

  Future<void> _runSession(
    StreamController<SttRecognitionEvent> controller,
    String? localeId,
  ) async {
    final ready = await _ensureInit();
    if (!ready) {
      if (!controller.isClosed) {
        controller.add(const SttFinalResult(text: '', confidence: 0));
        await controller.close();
      }
      return;
    }
    try {
      await _speech.listen(
        onResult: (result) {
          if (controller.isClosed) return;
          if (result.finalResult) {
            controller.add(SttFinalResult(
              text: result.recognizedWords,
              confidence: result.confidence,
            ));
            controller.close();
          } else {
            controller.add(SttPartialResult(
              text: result.recognizedWords,
              confidence: result.confidence,
            ));
          }
        },
        localeId: localeId,
        onDevice: true,
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
        cancelOnError: true,
      );
    } on Object catch (e) {
      if (!controller.isClosed) {
        controller.addError(e);
        await controller.close();
      }
    }
  }

  Future<bool> _ensureInit() async {
    if (_initialized) return true;
    _initialized = await _speech.initialize(
      onError: (_) {
        final controller = _controller;
        if (controller != null && !controller.isClosed) {
          controller.addError(StateError('speech recognizer reported error'));
        }
      },
      onStatus: (_) {},
      debugLogging: false,
    );
    return _initialized;
  }

  @override
  Future<void> stop() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _controller = null;
  }

  @override
  Future<void> cancel() async {
    if (_speech.isListening) {
      await _speech.cancel();
    }
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _controller = null;
  }
}
