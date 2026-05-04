# 16 — tts-integration

## Goal

Add **on-device text-to-speech** so a user can have a note read aloud. The reader is the OS native voice (Apple's `AVSpeechSynthesizer` on iOS / Android's `TextToSpeech` engine), wrapped by `TtsService` at `lib/services/speech/`. A "read aloud" affordance lives in the editor toolbar and on individual text blocks via long-press; tapping it streams the note's text to the speaker. Playback can be paused, resumed, and cancelled. Speech rate, pitch, and voice are picked from the OS's installed voices — no network lookup. After this spec, `package:flutter_tts` is imported only by `TtsService`.

This spec is small and well-bounded — `flutter_tts` is mature, the API is stable, and the OS-native engines are uniformly available offline (unlike STT, where Android's offline recognizer is patchy).

## Dependencies

- [10-theme-tokens](10-theme-tokens.md) — toolbar UI uses `context.tokens.*`.
- [06-bloc-migration-editor](06-bloc-migration-editor.md) — `NoteEditorBloc` extension pattern.
- [15-stt-integration](15-stt-integration.md) — sibling speech service; sits in `lib/services/speech/` next to `SttService`.

## Agents & skills

**Pre-coding skills:**
- `flutter-apply-architecture-best-practices` — `TtsService` wrapper conventions.
- `dart-add-unit-test` — bloc tests for the read-aloud lifecycle.

**After-coding agents:**
- `flutter-expert` — audit the overlay UI; word-level highlight has subtle text-painting performance considerations.
- `accessibility-tester` — TTS is itself an accessibility feature; verify VoiceOver / TalkBack labels on the overlay don't fight the synthesizer.

## Design Decisions

### Package: `flutter_tts` (^4.x)

- Maps to native engines: iOS `AVSpeechSynthesizer`, Android `TextToSpeech`.
- 100% offline by default — the OS engines bundle their own voices.
- Streaming progress callbacks (`setProgressHandler`) for word-level highlighting.
- Pause / resume / stop primitives.
- No transitive network deps — verified clean against the offline-imports gate.

### Surface

Two affordances:

1. **Editor toolbar — "Read note"**: speaks every text block in document order, skipping todo / image / audio blocks (audio blocks already have their own playback).
2. **Per-block long-press menu — "Read this block"**: scoped to one block. Useful for proofing a long note paragraph by paragraph.

A floating overlay (similar to the audio playback pill from Spec 13) appears while reading: shows the block being read, current word highlighted, with pause / stop buttons. On block completion the overlay advances to the next block automatically.

### Word-level highlight

`flutter_tts.setProgressHandler` reports `(text, startOffset, endOffset, word)`. We map the offset to the rendered text widget and underline the active word with `accent`. This is a meaningful "powerhouse" detail per the research findings — most note apps just play audio without visual sync.

### Voice + rate + pitch

Stored in `SettingsRepository` under three keys: `ttsVoice`, `ttsRate` (0.5–1.5, default 1.0), `ttsPitch` (0.5–1.5, default 1.0). Settings UI for adjusting them is added in a later settings-overhaul spec. For Spec 16 the values are read at start-of-playback and applied via the plugin. Voice list = `flutter_tts.getVoices()` filtered to the current locale.

### Cancellation

- The bloc's `close()` calls `_tts.stop()`.
- Tapping the stop button on the playback overlay calls `_tts.stop()`.
- Backgrounding the app on iOS auto-pauses; resume on foreground (the user can choose to resume manually via the overlay).

### Note skipping

When a block contains no plain text (image-only, audio-only), the engine skips it. Empty text blocks (zero non-whitespace chars) skip too. If the entire note has no readable content, the toolbar button shows briefly disabled with a tooltip "Nothing to read."

### Forbidden-imports gate

Append `package:flutter_tts` to the hygiene forbidden list with a carve-out for `lib/services/speech/tts_service.dart`.

## Implementation

### A. Files to create

```
lib/services/speech/
├── tts_service.dart
└── tts_models.dart                ← TtsVoice, TtsProgress

lib/features/note_editor/widgets/
└── read_aloud_overlay.dart        ← floating control while reading

test/services/speech/
└── fake_tts_service.dart
```

### B. `pubspec.yaml`

```yaml
dependencies:
  flutter_tts: ^4.2.0
```

### C. `lib/services/speech/tts_models.dart`

```dart
import 'package:equatable/equatable.dart';

class TtsVoice extends Equatable {
  const TtsVoice({required this.name, required this.locale});
  final String name;
  final String locale;
  @override
  List<Object?> get props => [name, locale];
}

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
```

### D. `lib/services/speech/tts_service.dart`

```dart
import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'tts_models.dart';

abstract class TtsService {
  Future<List<TtsVoice>> availableVoices();

  /// Speaks [text]. Returns a stream that emits [TtsProgress] per word and
  /// closes when speech completes (or [stop]/[pause] is called and resumed).
  Stream<TtsProgress> speak(
    String text, {
    String? voiceName,
    double rate = 1.0,
    double pitch = 1.0,
  });

  Future<void> pause();
  Future<void> stop();
  bool get isSpeaking;
}

class PluginTtsService implements TtsService {
  PluginTtsService() : _tts = FlutterTts();
  final FlutterTts _tts;

  bool _speaking = false;

  @override
  bool get isSpeaking => _speaking;

  @override
  Future<List<TtsVoice>> availableVoices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => TtsVoice(
              name: (m['name'] ?? '').toString(),
              locale: (m['locale'] ?? '').toString(),
            ))
        .toList();
  }

  @override
  Stream<TtsProgress> speak(
    String text, {
    String? voiceName,
    double rate = 1.0,
    double pitch = 1.0,
  }) async* {
    final controller = StreamController<TtsProgress>();
    if (voiceName != null) {
      // flutter_tts API: setVoice expects {name, locale}; locale resolved
      // from the available voices list. Implementer wires the lookup.
    }
    await _tts.setSpeechRate(rate.clamp(0.1, 2.0).toDouble());
    await _tts.setPitch(pitch.clamp(0.5, 2.0).toDouble());

    _tts.setProgressHandler((t, start, end, word) {
      if (!controller.isClosed) {
        controller.add(TtsProgress(text: t, start: start, end: end, word: word));
      }
    });
    _tts.setCompletionHandler(() async {
      _speaking = false;
      await controller.close();
    });
    _tts.setCancelHandler(() async {
      _speaking = false;
      await controller.close();
    });

    _speaking = true;
    await _tts.speak(text);
    yield* controller.stream;
  }

  @override
  Future<void> pause() async {
    await _tts.pause();
  }

  @override
  Future<void> stop() async {
    _speaking = false;
    await _tts.stop();
  }
}
```

### E. `NoteEditorBloc` extension

Events:

```dart
final class ReadAloudRequested extends NoteEditorEvent {
  const ReadAloudRequested({this.blockIndex});
  final int? blockIndex;   // null = read whole note from current position
  @override
  List<Object?> get props => [blockIndex];
}

final class ReadAloudPaused extends NoteEditorEvent {
  const ReadAloudPaused();
}

final class ReadAloudStopped extends NoteEditorEvent {
  const ReadAloudStopped();
}

final class _ReadAloudProgress extends NoteEditorEvent {
  const _ReadAloudProgress(this.progress);
  final TtsProgress progress;
  @override
  List<Object?> get props => [progress];
}

final class _ReadAloudBlockCompleted extends NoteEditorEvent {
  const _ReadAloudBlockCompleted();
}
```

State additions:

```dart
final bool isReadingAloud;
final int? currentReadBlockIndex;
final TtsProgress? readProgress;     // word-level highlight target
```

Bloc handlers extract block text, pipe through `_tts.speak(...)`, advance to the next text block on completion, stop when the note ends or user cancels. Cancellation in `close()` calls `_tts.stop()`.

Block-text extraction helper:

```dart
List<({int index, String text})> _readableBlocks(Note note) {
  final out = <({int index, String text})>[];
  for (var i = 0; i < note.blocks.length; i++) {
    final b = note.blocks[i];
    if (b['type'] == 'text') {
      final t = (b['content'] ?? '').toString().trim();
      if (t.isNotEmpty) out.add((index: i, text: t));
    } else if (b['type'] == 'checklist') {
      // Read each checked/unchecked item with a marker prefix.
      final items = (b['items'] as List?)?.cast<Map>() ?? const [];
      final lines = items.map((m) {
        final checked = m['checked'] == true ? 'done' : 'todo';
        return '$checked: ${m['content'] ?? ''}';
      }).join('. ');
      if (lines.trim().isNotEmpty) out.add((index: i, text: lines));
    }
    // Audio + image blocks are skipped; see "Note skipping" in design.
  }
  return out;
}
```

### F. `read_aloud_overlay.dart`

A floating banner anchored at the bottom of the editor while `state.isReadingAloud` is true:

```
┌────────────────────────────────────────┐
│  Reading block 2 of 4                   │
│  "...the quick brown FOX jumps..."      │   ← FOX highlighted in accent
│  [‖] [■]                                │
└────────────────────────────────────────┘
```

The current word is rendered in `tokens.colors.accent`; the surrounding text in `tokens.colors.onSurface`. Pause / stop buttons dispatch the corresponding events.

### G. `lib/main.dart`

```dart
RepositoryProvider<TtsService>.value(value: PluginTtsService()),
```

`NoteEditorBloc` factory site reads `ctx.read<TtsService>()`.

### H. `SettingsRepository` augmentation

Add three keys to the existing `settings_v2` box: `ttsVoice` (String?), `ttsRate` (double), `ttsPitch` (double). Defaults: null voice (= OS default), 1.0, 1.0. Setters + getters on the abstract `SettingsRepository`.

### I. Forbidden-imports gate

Append to `scripts/.forbidden-imports.txt`:

```
# Hygiene gate (use TtsService wrapper):
package:flutter_tts
```

Append to `scripts/.offline-allowlist`:

```
# Spec 16: allowed inside the TTS wrapper.
lib/services/speech/tts_service.dart
```

### J. Tests

- `fake_tts_service.dart` — controllable `speak()` stream via test helpers `emitProgress(...)`, `complete()`, `cancel()`.
- `note_editor_bloc_read_aloud_test.dart` — covers ReadAloudRequested with empty note (no-op), with one text block (single block read + completion), with multi-block (advances index), pause, stop.

### K. Update `context/architecture.md`, `code-standards.md`, `progress-tracker.md`

- Architecture stack: add `flutter_tts ^4` row.
- Code-standards forbidden imports: add `flutter_tts`.
- Progress tracker: mark Spec 16 complete; architecture decision 23 (TTS wrapper, native engines, word-level progress, three-key settings); no new open questions of substance.

## Success Criteria

- [ ] Files in Section A exist; `TtsService` wraps `flutter_tts`.
- [ ] `pubspec.yaml` adds `flutter_tts` only.
- [ ] `bash scripts/check-offline.sh` exits 0 with the new entry; carve-out works.
- [ ] `flutter analyze`, `flutter test`, `dart format -l 100` all clean.
- [ ] **Manual smoke**:
  - Open a note with three text blocks → tap "Read aloud" in toolbar → overlay appears → words highlight as spoken → block index advances → speech ends → overlay dismisses.
  - Tap pause → speech pauses → tap resume → speech continues from same offset.
  - Tap stop → speech ends immediately, overlay dismisses.
  - Long-press a single text block → "Read this block" → only that block reads.
  - Empty note (no readable text) → toolbar button shows "Nothing to read" tooltip; no playback starts.
  - Airplane mode: TTS works unchanged (proves on-device).
- [ ] No file under `lib/` outside `lib/services/speech/` imports `package:flutter_tts`.
- [ ] `NoteEditorBloc.close()` calls `_tts.stop()` if `isReadingAloud`.
- [ ] No invariant in `context/architecture.md` is changed.

## References

- [`context/architecture.md`](../context/architecture.md) — invariant 1 (still no network), invariant 8 (cancellation)
- [`context/project-overview.md`](../context/project-overview.md) — TTS is in-scope MVP
- [15-stt-integration](15-stt-integration.md), [13-audio-capture](13-audio-capture.md)
- Plugin: <https://pub.dev/packages/flutter_tts>
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md)
- Agent: `flutter-expert` — invoke after the overlay UI; word-level highlight has subtle text-painting performance considerations
- Agent: `accessibility-tester` — TTS is itself an accessibility feature; verify VoiceOver / TalkBack labels on the overlay
- Follow-up: Spec 17 (device-capability-service) — voices on lower-end devices have known glitches; capability probe extension can hide TTS on tested-broken hardware.
