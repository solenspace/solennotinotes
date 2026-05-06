import 'package:equatable/equatable.dart';

/// A voice the OS reports as installed for text-to-speech. Returned by
/// [TtsService.availableVoices]. The plugin's underlying map carries
/// additional fields (gender, network/local flag) that v1 does not surface.
class TtsVoice extends Equatable {
  const TtsVoice({required this.name, required this.locale});

  final String name;
  final String locale;

  @override
  List<Object?> get props => [name, locale];
}

/// A per-word progress sample emitted while [TtsService] is speaking. The
/// `[start, end)` half-open interval indexes into the original `text` so the
/// editor's read-aloud overlay can underline the active word with a single
/// `Text.rich` slice — no offset arithmetic at the call site.
class TtsProgress extends Equatable {
  const TtsProgress({
    required this.text,
    required this.start,
    required this.end,
    required this.word,
  });

  final String text;
  final int start;
  final int end;
  final String word;

  @override
  List<Object?> get props => [text, start, end, word];
}

/// Sealed parent for events emitted by [TtsService.speak]. The bloc's
/// listener is an exhaustive `switch (event)`; a new variant must be added
/// here and routed in the listener. Same shape as `SttRecognitionEvent`.
sealed class TtsEvent extends Equatable {
  const TtsEvent();
}

/// Streamed once per word while the synthesizer is speaking the current
/// block. Maps directly to the plugin's `setProgressHandler` callback.
final class TtsProgressEvent extends TtsEvent {
  const TtsProgressEvent(this.progress);

  final TtsProgress progress;

  @override
  List<Object?> get props => [progress];
}

/// Emitted exactly once per [TtsService.speak] call when the synthesizer
/// finishes the supplied text or when the session is cancelled. The bloc
/// uses this to advance to the next readable block.
final class TtsBlockCompleted extends TtsEvent {
  const TtsBlockCompleted();

  @override
  List<Object?> get props => const [];
}
