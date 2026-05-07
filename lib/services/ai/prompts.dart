import 'ai_action.dart';

/// Frozen prompt templates for the three AI assist actions. Locked
/// verbatim from Spec 20 § "Three actions, hand-tuned prompts" — these
/// strings are part of the product, not configuration. A change to a
/// template is a spec edit + a new architecture-decision entry, not a
/// silent runtime tweak.
///
/// English-only at MVP. Localization is a future spec; when it lands,
/// the per-locale strings live next to a locale key here, not inside
/// widgets.
class AiPrompts {
  const AiPrompts._();

  /// Build the full prompt for [action] with the user's [noteText]
  /// interpolated. The template is sealed; no other knobs are exposed
  /// to widgets so the prompt can be audited from this single file.
  static String build(AiAction action, String noteText) => switch (action) {
        AiAction.summarize =>
          'Summarize this note in 2–3 sentences. Be specific; preserve names, dates, decisions.\n\nNote:\n$noteText',
        AiAction.rewrite =>
          'Rewrite this note for clarity, keeping every fact. Same length.\n\nNote:\n$noteText',
        AiAction.suggestTitle =>
          'Suggest 5 short titles (≤ 7 words each) for this note. Output one per line, numbered.\n\nNote:\n$noteText',
      };
}
