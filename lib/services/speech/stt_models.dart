import 'package:equatable/equatable.dart';

/// Sealed parent for events emitted by [SttService.startDictation]. The
/// bloc's listener is an exhaustive `switch (event)`; a new variant must
/// be added here and routed in the listener.
sealed class SttRecognitionEvent extends Equatable {
  const SttRecognitionEvent();
}

/// Streamed while the recognizer is mid-utterance. The text grows as words
/// are recognized; the bloc renders it as italic preview in the active
/// text block but does not persist until the matching [SttFinalResult].
final class SttPartialResult extends SttRecognitionEvent {
  const SttPartialResult({required this.text, required this.confidence});

  final String text;
  final double confidence;

  @override
  List<Object?> get props => [text, confidence];
}

/// Emitted exactly once per session — when the recognizer signals end of
/// utterance, when [SttService.stop] is called, or when an offline-incapable
/// session is short-circuited (defence-in-depth: empty text, zero confidence).
final class SttFinalResult extends SttRecognitionEvent {
  const SttFinalResult({required this.text, required this.confidence});

  final String text;
  final double confidence;

  @override
  List<Object?> get props => [text, confidence];
}

/// A locale the OS reports as installed offline. Returned by
/// [SttService.availableLocales].
class SttLocale extends Equatable {
  const SttLocale({required this.localeId, required this.name});

  final String localeId;
  final String name;

  @override
  List<Object?> get props => [localeId, name];
}
