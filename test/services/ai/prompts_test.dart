import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/services/ai/ai_action.dart';
import 'package:noti_notes_app/services/ai/prompts.dart';

/// Golden-string tests for [AiPrompts]. The prompt templates are part
/// of the product surface (Spec 20 § "Three actions, hand-tuned
/// prompts"); a silent edit would change every model output without a
/// review trail. This test fails the second a template drifts.
void main() {
  const note = 'Met Carla on Tue.\nDecision: ship Friday.';

  group('AiPrompts.build', () {
    test('summarize template includes preserve directive + note payload', () {
      final prompt = AiPrompts.build(AiAction.summarize, note);
      expect(
        prompt,
        'Summarize this note in 2–3 sentences. Be specific; preserve names, dates, decisions.\n\n'
        'Note:\n'
        'Met Carla on Tue.\n'
        'Decision: ship Friday.',
      );
    });

    test('rewrite template asks for clarity at same length', () {
      final prompt = AiPrompts.build(AiAction.rewrite, note);
      expect(
        prompt,
        'Rewrite this note for clarity, keeping every fact. Same length.\n\n'
        'Note:\n'
        'Met Carla on Tue.\n'
        'Decision: ship Friday.',
      );
    });

    test('suggestTitle template asks for 5 numbered short titles', () {
      final prompt = AiPrompts.build(AiAction.suggestTitle, note);
      expect(
        prompt,
        'Suggest 5 short titles (≤ 7 words each) for this note. Output one per line, numbered.\n\n'
        'Note:\n'
        'Met Carla on Tue.\n'
        'Decision: ship Friday.',
      );
    });

    test('empty note still produces a structurally valid prompt', () {
      final prompt = AiPrompts.build(AiAction.summarize, '');
      expect(prompt.endsWith('Note:\n'), isTrue);
    });
  });

  group('AiAction labels', () {
    test('label is sentence-case', () {
      expect(AiAction.summarize.label, 'Summarize');
      expect(AiAction.rewrite.label, 'Rewrite');
      expect(AiAction.suggestTitle.label, 'Suggest title');
    });

    test('description is one short sentence', () {
      for (final action in AiAction.values) {
        expect(action.description, isNotEmpty);
        expect(action.description.length, lessThan(120));
      }
    });
  });
}
