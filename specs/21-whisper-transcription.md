# 21 — whisper-transcription

## Goal

Transcribe **audio note blocks** to text on-device using a Whisper-class model. The user long-presses an audio block in the editor → "Transcribe" → progress overlay shows token streaming → transcript inserted as a sibling text block immediately after the audio block (or replaces the audio block, the user's choice). Whisper runs through the same `LlmRuntime` chosen in Spec 18 (or a sibling runtime if Whisper requires a different binding) — fully offline, fully local, gated by `AiTier.canRunWhisper`.

This complements Spec 15 (live STT during typing). STT is for "speak-to-type"; transcription is for "I already recorded audio, now turn it into text." Different latency profiles (transcription can take minutes for a long clip and that's acceptable; STT must be near-realtime).

## Dependencies

- [13-audio-capture](13-audio-capture.md) — provides the audio file at `<app_documents>/notes/<note_id>/audio/<audio_id>.m4a`.
- [17-device-capability-service](17-device-capability-service.md) — `aiTier.canRunWhisper`.
- [18-llm-runtime-validation](18-llm-runtime-validation.md) — runtime + Whisper model decision.
- [19-llm-model-download](19-llm-model-download.md) — Whisper model is a second download, follows the same allowlist pattern.

## Agents & skills

**Pre-coding skills:**
- `flutter-apply-architecture-best-practices` — sibling runtime + cubit pattern (mirrors LLM).
- `dart-add-unit-test` — cubit tests for the transcription lifecycle.

**After-coding agents:**
- `flutter-expert` — invoke after the runtime wiring; on-device Whisper has subtle audio-format gotchas (sample rate, mono vs stereo, m4a vs wav).
- `accessibility-tester` — the result review buttons need readable VoiceOver labels.

## Design Decisions

### Whisper variant

Per progress-tracker open question 2, choose between:

- **`whisper-tiny.en`** (~75 MB, ~10× realtime on `AiTier.compact`).
- **`whisper-base.en`** (~140 MB, ~6× realtime on `AiTier.compact`, more accurate).

Default: `whisper-base.en` on `AiTier.full`, `whisper-tiny.en` on `AiTier.compact`. Implementer can override after Spec 18 benchmarks.

### Same allowlist as the LLM

Whisper model file follows Spec 19's flow: explicit opt-in, one-time download, hash-verified, stored in `<app_support>/whisper/<model>.bin`. The download URL adds one more line to `scripts/.offline-allowlist`. The downloader code is **the same `LlmModelDownloader`** from Spec 19, parameterized by `(filename, url, sha256)`.

### Per-block transcription, not whole-note

Each audio block transcribes independently. This:

- Keeps generation cancellable per block.
- Lets the user transcribe only some audio blocks if they want.
- Avoids one giant prompt for notes with multiple audio blocks.

### UX

1. Long-press the audio block pill (existing menu from Spec 13) → new "Transcribe" entry.
2. On tap: a small overlay attached to the block shows a progress indicator (no token streaming for transcription — Whisper outputs whole words at once, not token-by-token like an LLM).
3. On completion: the user is offered "Insert below" / "Replace audio with transcript" / "Discard".
4. The transcript renders as a regular text block; the original audio file is preserved unless the user chose Replace.

### State

`TranscriptionCubit` per audio block (mounted by the block's view when transcription starts; disposed after). State holds `phase` (`idle | running | ready | failed`), `progress` (0–1), `result` (the transcript string).

### Cancellation

Tapping cancel calls `whisperRuntime.cancel()`; the bloc emits `phase: idle`, the overlay dismisses. Cancellation is supported by all candidate Whisper runtimes; this is part of the Spec 18 validation criteria.

## Implementation

### A. Files to create

```
lib/services/ai/
├── whisper_runtime.dart         ← interface; concrete impl wires the chosen package
└── whisper_model_constants.dart ← URL + hash + filename for the chosen variant

lib/features/note_editor/cubit/
├── transcription_cubit.dart
└── transcription_state.dart

lib/features/note_editor/widgets/
└── transcription_overlay.dart
```

### B. `WhisperRuntime` interface

```dart
abstract class WhisperRuntime {
  Future<bool> load({required String modelPath});

  /// Transcribes [audioFilePath]. Emits progress 0..1 then a final result.
  /// Cancels cleanly when the stream subscription is cancelled.
  Stream<TranscriptionEvent> transcribe({required String audioFilePath});

  Future<void> unload();
}

sealed class TranscriptionEvent {
  const TranscriptionEvent();
}

class TranscriptionProgress extends TranscriptionEvent {
  const TranscriptionProgress(this.fraction);
  final double fraction;
}

class TranscriptionResult extends TranscriptionEvent {
  const TranscriptionResult(this.text);
  final String text;
}
```

### C. Cubit

```dart
class TranscriptionCubit extends Cubit<TranscriptionState> {
  TranscriptionCubit({required WhisperRuntime runtime})
      : _runtime = runtime,
        super(const TranscriptionState());

  final WhisperRuntime _runtime;
  StreamSubscription<TranscriptionEvent>? _sub;

  Future<void> start(String path) async {
    emit(state.copyWith(phase: TranscriptionPhase.running, progress: 0));
    _sub = _runtime.transcribe(audioFilePath: path).listen(
      (event) {
        if (event is TranscriptionProgress) {
          emit(state.copyWith(progress: event.fraction));
        } else if (event is TranscriptionResult) {
          emit(state.copyWith(
            phase: TranscriptionPhase.ready,
            result: event.text,
            progress: 1.0,
          ));
        }
      },
      onError: (e, _) {
        emit(state.copyWith(
          phase: TranscriptionPhase.failed,
          errorMessage: e.toString(),
        ));
      },
    );
  }

  Future<void> cancel() async {
    await _sub?.cancel();
    _sub = null;
    emit(const TranscriptionState());
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
```

### D. UI overlay

`TranscriptionOverlay` is a small floating banner anchored above the audio block while transcription is running. Shows progress as a determinate bar (Whisper reports `fraction` based on chunks processed). On `ready`, the banner expands into a result review with three buttons: Insert below, Replace audio, Discard.

### E. Audio block menu integration

In `audio_block_view.dart` (from Spec 13), extend the long-press menu:

```dart
{
  if (deviceCaps.aiTier.canRunWhisper && whisperReady) 'Transcribe',
  'Re-record',
  'Delete',
  if (shareSpecLanded) 'Share',
}
```

Tapping Transcribe creates a `TranscriptionCubit`, calls `start(path)`, mounts the overlay.

### F. Allowlist + downloader reuse

`scripts/.offline-allowlist` gains:

```
# Spec 21: Whisper model download via the LlmModelDownloader.
# (Same downloader path; new URL constant in WhisperModelConstants.)
```

The downloader path is already allowlisted. We add a `WhisperReadinessCubit` (sibling to `LlmReadinessCubit`) that uses the same `LlmModelDownloader` parameterized for the Whisper file.

### G. AI settings — second model row

The "Manage AI" screen from Spec 20 gains a second row:

- "Voice transcription" — model name, size, status, re-download / delete buttons.

User can enable Whisper without enabling the LLM and vice versa; they're independent capabilities.

### H. Insert / Replace handlers

- **Insert below**: dispatch `BlocksReplaced(newBlocks)` where `newBlocks` is the existing list with a text block inserted after the source audio block.
- **Replace audio**: dispatch `BlocksReplaced(newBlocks)` substituting the audio block for the new text block; also dispatch `AudioBlockRemoved(audioId)` so the file is cleaned up.
- **Discard**: cubit `cancel()`; nothing changes.

## Success Criteria

- [ ] Files in Section A exist; long-press menu on audio blocks shows "Transcribe" only when caps + readiness gate is open.
- [ ] **Manual smoke** on `AiTier.full` device with Whisper model downloaded:
  - Record a 30s audio note → long-press → Transcribe → progress fills → result appears in ~5s → Insert below → text block follows the audio block in the editor.
  - Same flow on `AiTier.compact` with whisper-tiny.en.
  - Cancel mid-transcription → overlay dismisses → no partial transcript saved.
  - On `AiTier.unsupported` or with Whisper model absent: Transcribe option does not appear in the menu.
- [ ] Airplane mode during transcription: works unchanged.
- [ ] No file under `lib/` outside `lib/services/ai/` imports the Whisper runtime package.
- [ ] `flutter analyze` / format / test clean; offline gate exempts only the model download path.
- [ ] No invariant changed.

## References

- [13-audio-capture](13-audio-capture.md), [17](17-device-capability-service.md), [18](18-llm-runtime-validation.md), [19](19-llm-model-download.md), [20](20-ai-assist-ui.md)
- [`context/architecture.md`](../context/architecture.md) — invariants 1, 2, 8
- [progress-tracker.md](../context/progress-tracker.md) — open question 2 (Whisper variant)
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md)
- Agent: `flutter-expert` — invoke after the runtime wiring; on-device Whisper has subtle audio-format gotchas (sample rate, mono vs stereo)
- Follow-up: Spec 22 (P2P transport) — shared notes might travel with their transcripts; decide encoding in that spec.
