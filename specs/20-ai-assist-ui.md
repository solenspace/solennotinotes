# 20 — ai-assist-ui

## Goal

Add the **AI assist UI** in the editor: a small "✦ Assist" affordance (gated by `AiTier.canRunLlm` AND `LlmReadinessCubit.isReady`) opens a bottom sheet with three actions — **Summarize**, **Rewrite**, **Suggest title**. Tapping an action streams the LLM's tokens into a draft preview pane; the user accepts (replace / append) or discards. All inference runs on-device via the `LlmRuntime` from Spec 18; no network, no telemetry, no logging off-device. The ai actions take the current note's text content as input and produce a clean, reviewable result the user explicitly chooses to apply.

This is the **second UI-heavy spec** after Spec 11 (overlay picker) — the patterns established there (bottom sheet, App Style chrome, BlocBuilder/BlocListener) carry over. UI research informed the streaming visualization (research finding: "AI features feel more powerful when tokens visibly stream rather than appearing fully-formed").

## Dependencies

- [17-device-capability-service](17-device-capability-service.md) — `aiTier` gates the affordance.
- [18-llm-runtime-validation](18-llm-runtime-validation.md) — `LlmRuntime` interface defines `generate(prompt) → Stream<String>`.
- [19-llm-model-download](19-llm-model-download.md) — model file present and hash-verified.
- [11-noti-theme-overlay](11-noti-theme-overlay.md) — picker pattern, contrast guardrails, App Style chrome.

## Agents & skills

**Pre-coding skills:**
- `flutter-build-responsive-layout` — sheet sizing for the streaming pane on small + large devices.
- `flutter-add-widget-test` — coverage for the streaming/accept/discard flows.

**After-coding agents:**
- `flutter-expert` — sheet + streaming + cancellation triangle is easy to deadlock; verify `LlmRuntime.unload()` cancels generation cleanly.
- `ui-designer` — the streaming pane must read as alive (cursor blink, signature glyph pulse), not janky.
- `accessibility-tester` — streaming text needs `Semantics(liveRegion: true)` so screen readers announce; the ✦ glyph needs a label.

## Design Decisions

### Three actions, hand-tuned prompts

Each action has a fixed prompt template with the note's text interpolated. Templates live in `lib/services/ai/prompts.dart` as `const String` values — versioned with the spec, no runtime mutation.

- **Summarize**: "Summarize this note in 2–3 sentences. Be specific; preserve names, dates, decisions. Note:\n\n{TEXT}"
- **Rewrite**: "Rewrite this note for clarity, keeping every fact. Same length. Note:\n\n{TEXT}"
- **Suggest title**: "Suggest 5 short titles (≤ 7 words each) for this note. Output one per line, numbered. Note:\n\n{TEXT}"

Prompts are plain English, English-only at MVP. Localization is a future spec.

### Streaming UX

When an action runs:

1. Bottom sheet opens with a centered streaming pane.
2. Tokens append to the pane as they arrive — the cursor blinks at the streaming position.
3. A subtle "tinking" pulse animation (the user's `signatureAccent` glyph if present, else a small dot) sits above the text while the model is generating.
4. **Stop** button (always visible) cancels the stream — bloc dispatches `LlmRuntime.unload()` to halt generation cleanly.
5. On stream end:
   - If the user has typed in the editor below during generation, the result is held; we don't clobber unsaved input.
   - **Accept** options: Replace the source text · Append below · Insert as title (suggest-title only) · Dismiss.

### Latency feedback

`AiTier.compact` devices may take 30–60s for a multi-paragraph summarize. The UI:

- Shows a "first token in 5–15s" hint until the first token arrives, so users don't think the app froze.
- Once tokens stream, the hint disappears.
- An overall elapsed timer shows in the bottom-right of the sheet.

### The "✦ Assist" toolbar button

Lives in the editor toolbar next to the paintbrush (theme overlay). It uses the user's `signatureAccent` glyph if set; otherwise a default ✦ icon. The button is hidden completely when:

- `aiTier.canRunLlm` is false (covered by Spec 17 gate), OR
- `LlmReadinessCubit` state is not `ready` (covered by Spec 19).

Long-press → "Manage AI" → opens the AI settings screen (where the user can re-download or delete the model).

### State

`AiAssistCubit` per-route, mounted alongside `NoteEditorBloc`:

```dart
class AiAssistState extends Equatable {
  final AiAction? activeAction;       // summarize | rewrite | suggestTitle | null
  final String draftOutput;           // accumulating tokens
  final bool isGenerating;
  final Duration elapsed;
  final String? errorMessage;
  // ...
}
```

### Result handling — accept paths

- **Replace**: dispatches `BlocksReplaced(newBlocks)` on `NoteEditorBloc` where `newBlocks` substitutes the source text block(s) with one new text block carrying the AI output.
- **Append**: pushes a new text block onto `note.blocks` after the last block.
- **As title**: dispatches `TitleChanged(line)` with the user-selected line from suggest-title's numbered list.

The cubit never writes to `NotesRepository` directly — every mutation flows through `NoteEditorBloc` so audit trails stay coherent.

### Privacy reinforcement

- The sheet header carries a small line: "Running on this device — nothing leaves it."
- After result accept, the draft is cleared from cubit memory immediately (no holding onto generated text after use).

## Implementation

### A. Files to create

```
lib/services/ai/
├── llm_runtime.dart            ← interface from Spec 18, concrete impl wires the chosen package
├── prompts.dart                ← three const prompt templates
└── ai_action.dart              ← enum: summarize, rewrite, suggestTitle

lib/features/note_editor/cubit/
├── ai_assist_cubit.dart
└── ai_assist_state.dart

lib/features/note_editor/widgets/
├── ai_assist_button.dart       ← toolbar trigger
├── ai_assist_sheet.dart        ← three-action sheet + streaming pane
└── ai_streaming_pane.dart      ← token-by-token rendering with cursor

test/features/note_editor/cubit/
└── ai_assist_cubit_test.dart
```

### B. `ai_action.dart`

```dart
enum AiAction {
  summarize,
  rewrite,
  suggestTitle;

  String get label => switch (this) {
        AiAction.summarize => 'Summarize',
        AiAction.rewrite => 'Rewrite',
        AiAction.suggestTitle => 'Suggest title',
      };
}
```

### C. `prompts.dart`

```dart
import 'ai_action.dart';

class AiPrompts {
  static String build(AiAction action, String noteText) => switch (action) {
        AiAction.summarize =>
            'Summarize this note in 2–3 sentences. Be specific; preserve names, dates, decisions.\n\nNote:\n$noteText',
        AiAction.rewrite =>
            'Rewrite this note for clarity, keeping every fact. Same length.\n\nNote:\n$noteText',
        AiAction.suggestTitle =>
            'Suggest 5 short titles (≤ 7 words each) for this note. Output one per line, numbered.\n\nNote:\n$noteText',
      };

  const AiPrompts._();
}
```

### D. `AiAssistCubit`

Holds active action, accumulating output, generating flag, timer. `start(action, noteText)` calls `LlmRuntime.generate(...)` and pipes tokens. `stop()` calls `LlmRuntime.unload()` and emits `isGenerating: false`. `accept(target)` returns the final string; the calling sheet dispatches the right `NoteEditorBloc` event.

### E. UI sheet

`AiAssistSheet` mirrors the structure of `OverlayPickerSheet` from Spec 11: bottom sheet, drag handle, three tabs (one per action). Each tab is a button with the action label + a one-line description; tapping starts generation in the same sheet (sheet expands to show the streaming pane).

`AiStreamingPane` renders the `state.draftOutput` text with:

- A blinking `▎` cursor at end while `isGenerating`.
- The user's `signatureAccent` glyph (or ✦) pulsing above the text.
- Elapsed timer in bottom-right.
- Stop button.

After generation ends, the pane swaps to result mode: the text becomes selectable, three accept buttons appear (Replace / Append / Dismiss; Replace becomes "Use this title" for suggestTitle; user picks a line via radio).

### F. Toolbar wiring

`AiAssistButton`:

```dart
return BlocSelector<LlmReadinessCubit, LlmReadinessState, bool>(
  selector: (s) => s.phase == LlmReadinessPhase.ready,
  builder: (ctx, ready) {
    final tier = ctx.read<DeviceCapabilityService>().aiTier;
    if (!tier.canRunLlm || !ready) return const SizedBox.shrink();
    return IconButton(
      icon: _AssistGlyph(),
      onPressed: () => AiAssistSheet.show(ctx),
    );
  },
);
```

### G. Settings — Manage AI

Long-pressing the toolbar button (or via a Settings → AI row) opens a small screen with:

- Model name + version.
- Download date + size.
- "Re-download model" button.
- "Delete model and disable AI" button.

This rounds out the lifecycle started in Spec 19.

## Success Criteria

- [ ] Files in Section A exist; toolbar button renders only when `aiTier.canRunLlm && LlmReadiness == ready`.
- [ ] **Manual smoke** on `AiTier.full` device with model downloaded:
  - Open a note with at least one paragraph → ✦ button appears → tap → sheet opens → tap Summarize → tokens stream → 50–80 word summary appears → tap Replace → editor's source text block is replaced.
  - Repeat with Rewrite → editor's text retains every fact, rephrased.
  - Repeat with Suggest title → 5 numbered options → pick one → note title updates.
  - Tap Stop mid-stream → generation halts within 1s → partial output discarded.
- [ ] Airplane mode during AI use: works unchanged (zero network).
- [ ] On `AiTier.compact`: same flow, slower generation, "first token in 5–15s" hint visible until first token.
- [ ] No file under `lib/` outside `lib/services/ai/` imports the chosen LLM package directly.
- [ ] `flutter analyze` / format / test clean; offline gate clean.
- [ ] No invariant in `context/architecture.md` is changed.

## References

- [`context/architecture.md`](../context/architecture.md) — invariants 1, 2, 8
- [11-noti-theme-overlay](11-noti-theme-overlay.md) — sheet pattern reused
- [17](17-device-capability-service.md), [18](18-llm-runtime-validation.md), [19](19-llm-model-download.md)
- Skill: [`flutter-build-responsive-layout`](../.agents/skills/flutter-build-responsive-layout/SKILL.md)
- Agent: `flutter-expert` — sheet + streaming + cancellation triangle is easy to deadlock
- Agent: `ui-designer` — verify the streaming pane reads as alive, not janky
- Agent: `accessibility-tester` — the ✦ glyph + streaming text need readable VoiceOver labels
- Follow-up: Spec 21 (Whisper transcription) reuses the cubit pattern for audio → text.
