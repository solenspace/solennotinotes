import 'package:equatable/equatable.dart';

import 'package:noti_notes_app/services/ai/ai_action.dart';

/// State for [AiAssistCubit]. The shape mirrors Spec 20 § "State":
///
///   * [activeAction] is `null` while the sheet is on the picker tab and
///     becomes non-null when a generation is in flight or finished, so
///     the sheet can swap between picker / streaming / result modes
///     from a single field.
///   * [draftOutput] accumulates tokens as they arrive; the UI binds to
///     this field directly.
///   * [isGenerating] gates the cursor-blink, signature-glyph pulse,
///     and Stop button.
///   * [firstTokenArrived] drives the "first token in 5–15s" hint —
///     once a single token lands the hint is gone for the rest of the
///     run.
///   * [elapsed] is the wall-clock since [AiAssistCubit.start] was
///     called; ticks every second.
///   * [errorMessage] surfaces a model / runtime failure for the UI's
///     error mode.
///   * [finished] flips to `true` when the stream closes (success,
///     stop, or error) so the sheet swaps to result mode.
class AiAssistState extends Equatable {
  const AiAssistState({
    this.activeAction,
    this.draftOutput = '',
    this.isGenerating = false,
    this.firstTokenArrived = false,
    this.elapsed = Duration.zero,
    this.errorMessage,
    this.finished = false,
  });

  /// Initial state — picker is showing, nothing pending.
  const AiAssistState.initial()
      : activeAction = null,
        draftOutput = '',
        isGenerating = false,
        firstTokenArrived = false,
        elapsed = Duration.zero,
        errorMessage = null,
        finished = false;

  final AiAction? activeAction;
  final String draftOutput;
  final bool isGenerating;
  final bool firstTokenArrived;
  final Duration elapsed;
  final String? errorMessage;
  final bool finished;

  /// Parsed list of title candidates from a `suggestTitle` run. Returns an
  /// empty list when [activeAction] is not [AiAction.suggestTitle] or the
  /// model has not produced any numbered lines yet. Robust to the model
  /// emitting `1. Foo`, `1) Foo`, or `1 - Foo`; trims surrounding
  /// whitespace and discards empty candidates.
  List<String> get titleSuggestions {
    if (activeAction != AiAction.suggestTitle) return const [];
    final pattern = RegExp(r'^\s*\d+\s*[\.\)\-:]\s*(.+?)\s*$');
    final out = <String>[];
    for (final line in draftOutput.split('\n')) {
      final match = pattern.firstMatch(line);
      if (match == null) continue;
      final candidate = match.group(1)?.trim() ?? '';
      if (candidate.isEmpty) continue;
      out.add(candidate);
    }
    return out;
  }

  AiAssistState copyWith({
    AiAction? activeAction,
    String? draftOutput,
    bool? isGenerating,
    bool? firstTokenArrived,
    Duration? elapsed,
    String? errorMessage,
    bool? finished,
    bool clearActiveAction = false,
    bool clearError = false,
  }) {
    return AiAssistState(
      activeAction: clearActiveAction ? null : (activeAction ?? this.activeAction),
      draftOutput: draftOutput ?? this.draftOutput,
      isGenerating: isGenerating ?? this.isGenerating,
      firstTokenArrived: firstTokenArrived ?? this.firstTokenArrived,
      elapsed: elapsed ?? this.elapsed,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      finished: finished ?? this.finished,
    );
  }

  @override
  List<Object?> get props => [
        activeAction,
        draftOutput,
        isGenerating,
        firstTokenArrived,
        elapsed,
        errorMessage,
        finished,
      ];
}
