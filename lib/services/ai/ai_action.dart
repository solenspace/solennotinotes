/// Discrete AI assist action selectable from the editor's bottom sheet.
/// Each member maps 1:1 to a hand-tuned prompt template in
/// `prompts.dart`; changing this enum requires updating the template
/// switch and the sheet's tab list together.
///
/// Locked by Spec 20 § "Three actions, hand-tuned prompts" — the
/// product surface is intentionally small (three actions) at MVP so the
/// quality bar of each can be tuned without combinatorial explosion.
enum AiAction {
  /// Compress the note into 2–3 sentences while preserving names, dates,
  /// and decisions verbatim.
  summarize,

  /// Rephrase the note for clarity at the same length, preserving every
  /// fact.
  rewrite,

  /// Propose five short title candidates (≤ 7 words each), one per line.
  suggestTitle;

  /// Sentence-case label used by the sheet's action button. Voice + copy
  /// rule from `context/ui-context.md`: buttons are verbs, sentence case,
  /// no exclamation marks.
  String get label => switch (this) {
        AiAction.summarize => 'Summarize',
        AiAction.rewrite => 'Rewrite',
        AiAction.suggestTitle => 'Suggest title',
      };

  /// One-line description shown under the label in the sheet's action
  /// list. Kept short so a small phone reads three rows without scroll.
  String get description => switch (this) {
        AiAction.summarize => 'Tighten this note into a few sentences.',
        AiAction.rewrite => 'Rephrase for clarity, same length, every fact intact.',
        AiAction.suggestTitle => 'Five short title ideas to pick from.',
      };
}
