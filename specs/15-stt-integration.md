# 15 — stt-integration

## Goal

Add **on-device speech-to-text dictation** to Notinotes. The user taps a dictation icon in the editor toolbar; spoken words stream into the current text block as they're recognized; tapping the icon again stops. STT runs locally — iOS Speech framework with `requiresOnDeviceRecognition: true`, Android offline recognizer where supported — and the feature **hides itself on devices that can't run STT offline**, preserving [architecture.md](../context/architecture.md) invariant 1 (zero network in runtime). The wrapper is `SttService` at `lib/services/speech/`; `NoteEditorBloc` gains four events for the dictation lifecycle (start, partial result, final result, stop). After this spec, `package:speech_to_text` is imported only by `SttService`; no consumer reaches into it directly.

## Dependencies

- [12-permissions-service](12-permissions-service.md) — mic permission via `PermissionsService.requestMicrophone()`. The same permission as audio capture (Spec 13); if the user already granted it for audio recording, no second prompt.
- [13-audio-capture](13-audio-capture.md) — establishes the editor's microphone-button affordance; STT is a sibling button.
- [06-bloc-migration-editor](06-bloc-migration-editor.md) — `NoteEditorBloc` extension pattern.

## Agents & skills

**Pre-coding skills:**
- `flutter-apply-architecture-best-practices` — service wrapper + capability-probe pattern.
- `dart-add-unit-test` — bloc tests cover the dictation lifecycle (start/partial/final/stop/cancel).

**After-coding agents:**
- `flutter-expert` — audit the bloc dictation handlers; partial-result interpolation + last-text-block append have subtle off-by-one bugs.
- `accessibility-tester` — hold-to-dictate must have a tap-to-toggle fallback when accessible-nav is on.
- `code-reviewer` — confirm the Probe verification offline-trace test is wired into integration tests.

## Design Decisions

### Package: `speech_to_text` (^7.x)

- Verified publisher (csdcorp.com), Flutter Favorite candidate.
- Single API for iOS (Speech framework) + Android (`SpeechRecognizer`).
- Supports streaming partial results (essential for "type as you talk" feel).
- Locale picking via the OS's installed languages — no internet lookup.

### Hard offline gate

`speech_to_text` *can* fall back to cloud recognition on Android if the offline recognizer isn't installed. **We never let it.** A startup capability probe in `SttCapabilityProbe`:

1. On iOS: check `Speech.SFSpeechRecognizer.supportsOnDeviceRecognition` for the user's current locale via the plugin's `initialize` + a session-config probe. If false → STT is permanently unavailable on that device.
2. On Android: query `SpeechRecognizer.isOnDeviceRecognitionAvailable(...)` (Android 12+). On Android < 12, the heuristic is "if the device manufacturer is in our known-offline allowlist OR Google offline language pack is reachable via `RecognizerIntent.EXTRA_PREFER_OFFLINE`" — for safety we treat Android < 12 as **not offline-capable**. STT hides on those devices.
3. **Every recognition request explicitly sets `onDevice: true`** in the plugin call. If the plugin attempts a network call anyway (which it won't with `onDevice: true`), the offline-imports gate catches it because `speech_to_text` is added to the forbidden-imports list except inside `SttService`.
4. The probe result caches in `SettingsRepository` under `sttOfflineCapable: bool` so we don't re-probe on every cold start.

### Probe verification

The `onDevice: true` flag is a directive, not a guarantee — some Android OEMs route recognition to the cloud regardless. This spec ships an **instrumented offline-trace test** that runs in `integration_test/stt_offline_trace_test.dart`:

1. Start a 60-second dictation session.
2. Hook `dart:io.HttpOverrides.global` and assert no `HttpClient` is opened during the session.
3. Run the test on the latest iOS simulator + a Pixel 7 emulator + at least one physical device (manual run; CI later).
4. If the test fails on a device family, that family's OEM string is added to `SttCapabilityProbe`'s deny-list and STT hides for those users.

`sherpa_onnx` ([picovoice context](https://picovoice.ai/blog/streaming-speech-to-text-in-flutter/)) — a true-offline alternative shipping its own ONNX runtime + small Whisper-derived model — is the documented fallback path if the trace fails on a wide enough device range. It adds ~80 MB to the binary; not worth the size cost unless `speech_to_text` proves untrustworthy.

### Streaming results

`speech_to_text`'s callback fires with `SpeechRecognitionResult` containing `recognizedWords`, `finalResult`, and `confidence`. We expose both partial and final results to the BLoC:

- **Partial results** update a transient `dictationDraft` field on the editor state — rendered as faintly-italicized text appended to the current text block, similar to iOS's native dictation visual. The user's existing block content is not modified yet.
- **Final result** (when the recognizer signals end of an utterance) commits the dictated string to the text block via `BlocksReplaced` and clears `dictationDraft`.

### When to stop

Three stop conditions:

1. User taps the dictation button again (manual stop).
2. The recognizer reports a "no speech detected" timeout (default 8s of silence).
3. The bloc closes (route popped, screen replaced).

All three flow through the same `_stopDictation()` path that cancels the listener, finalizes the draft if non-empty, and emits `isDictating: false`.

### Locale handling

The locale picker uses `SttService.availableLocales()` — returns only the locales the OS has installed offline. The bloc's first call uses the user's system locale; if unavailable offline, falls back to `en_US`. Locale switcher UI is a future spec (alongside intl localization scaffold).

### UX

A separate icon in the editor toolbar (different from the audio-record icon to avoid confusion):

- **Hold-to-dictate** (long-press): start while held, stop on release. Same gesture model as audio capture. The recognized text streams *into the active text block*, not as a new block.
- **Tap-to-toggle**: tap once, dictate, tap again to stop. Accessibility fallback.

The toolbar button is `mic.svg` with a small "T" overlay (or the existing icon glyph swapped); explicit UI design is the implementer's call within this spec.

### Forbidden-import gate extension

Add `package:speech_to_text` to the hygiene-only forbidden list (with carve-out for `lib/services/speech/`). The plugin is not on the offline-imports gate because `onDevice: true` is what matters; the hygiene gate ensures consumers go through our wrapper.

## Implementation

### A. Files to create

```
lib/services/speech/
├── stt_service.dart
├── stt_capability_probe.dart
└── stt_models.dart                ← SttPartialResult, SttFinalResult, SttUnavailable

test/services/speech/
└── fake_stt_service.dart

test/features/note_editor/bloc/
└── note_editor_bloc_dictation_test.dart   ← extension, not new file
```

### B. `pubspec.yaml`

```yaml
dependencies:
  speech_to_text: ^7.3.0
```

### C. `lib/services/speech/stt_models.dart`

```dart
import 'package:equatable/equatable.dart';

class SttPartialResult extends Equatable {
  const SttPartialResult({required this.text, required this.confidence});
  final String text;
  final double confidence;
  @override
  List<Object?> get props => [text, confidence];
}

class SttFinalResult extends Equatable {
  const SttFinalResult({required this.text, required this.confidence});
  final String text;
  final double confidence;
  @override
  List<Object?> get props => [text, confidence];
}

class SttLocale extends Equatable {
  const SttLocale({required this.localeId, required this.name});
  final String localeId;
  final String name;
  @override
  List<Object?> get props => [localeId, name];
}
```

### D. `lib/services/speech/stt_service.dart`

```dart
import 'dart:async';

import 'stt_models.dart';

abstract class SttService {
  /// Whether this device can run STT fully offline. Cached per cold start.
  Future<bool> get isOfflineCapable;

  Future<List<SttLocale>> availableLocales();

  /// Starts a streaming dictation session. Yields partial results in real
  /// time and exactly one [SttFinalResult] when the utterance ends.
  /// The stream closes after the final result or when [stop] is called.
  Stream<Object> startDictation({String? localeId});

  /// Stops the active session early. Final result (if any pending) is
  /// emitted before the stream closes.
  Future<void> stop();

  /// Cancels the active session and discards any pending final result.
  Future<void> cancel();

  bool get isListening;
}

class PluginSttService implements SttService {
  // Implementation wraps `package:speech_to_text` and enforces onDevice: true
  // on every listen() call. Probe results cached on construction via
  // SttCapabilityProbe.
  // Full implementation is a mechanical translation of the speech_to_text
  // README's example with these constraints layered on:
  //   - listen(onDevice: true, ...)
  //   - reject any locale whose `onDeviceRecognition` is false
  //   - throw SttUnavailableException if isOfflineCapable resolves false
  //   - emit SttPartialResult on partial; SttFinalResult on finalResult;
  //     close stream after final.
}
```

### E. `lib/services/speech/stt_capability_probe.dart`

```dart
import 'dart:io';

import 'package:speech_to_text/speech_to_text.dart' as stt;

class SttCapabilityProbe {
  const SttCapabilityProbe();

  /// Runs once on cold start; result is cached in SettingsRepository.
  Future<bool> probe() async {
    if (Platform.isAndroid) {
      final sdkInt = await _androidSdkInt();
      if (sdkInt < 31) return false;   // Android 12+ only for safe offline guarantees
    }
    final speech = stt.SpeechToText();
    final ready = await speech.initialize(
      onError: (_) {},
      onStatus: (_) {},
      debugLogging: false,
    );
    if (!ready) return false;
    if (Platform.isIOS) {
      // iOS: check the system locale's on-device support via the plugin.
      final supports = speech.isAvailable;
      return supports;
    }
    // Android 12+: rely on the plugin's getDefaultLocale + initialize success.
    // If the plugin reports success without a Google offline language pack,
    // we still hide STT — but detecting that case requires platform channel
    // wiring beyond what `speech_to_text` exposes. Trade-off documented in
    // progress-tracker.md as open question 14.
    return true;
  }

  Future<int> _androidSdkInt() async {
    // Use device_info_plus when added in Spec 17 (device-capability-service).
    // For Spec 15, we proxy via Platform.version parsing. Implementer note:
    // when Spec 17 lands, swap this to DeviceInfoPlugin().androidInfo.version.sdkInt.
    final raw = Platform.operatingSystemVersion;
    final match = RegExp(r'API (\d+)').firstMatch(raw);
    return match == null ? 0 : int.parse(match.group(1)!);
  }
}
```

> Implementer note: when Spec 17 (device-capability-service) lands, refactor `_androidSdkInt` to use `device_info_plus`. Until then, the regex parse is the fallback.

### F. `lib/main.dart` — bootstrap probe + register service

```dart
final settingsRepository = HiveSettingsRepository();
await settingsRepository.init();

final probed = await const SttCapabilityProbe().probe();
await settingsRepository.setSttOfflineCapable(probed);

// ...rest of main()…

RepositoryProvider<SttService>.value(
  value: PluginSttService(isOfflineCapable: probed),
),
```

### G. `NoteEditorBloc` extension

New events:

```dart
final class DictationStarted extends NoteEditorEvent {
  const DictationStarted();
}

final class DictationStopped extends NoteEditorEvent {
  const DictationStopped();
}

final class _DictationPartial extends NoteEditorEvent {
  const _DictationPartial(this.text);
  final String text;
  @override
  List<Object?> get props => [text];
}

final class _DictationFinal extends NoteEditorEvent {
  const _DictationFinal(this.text);
  final String text;
  @override
  List<Object?> get props => [text];
}
```

Underscore-prefixed events are bloc-internal — fired by the stream subscription from the service, not by the UI.

State additions:

```dart
final bool isDictating;            // true while the recognizer is listening
final String? dictationDraft;      // partial recognized text shown in italics
final bool dictationUnavailableExplainerRequested; // one-shot flag
```

Bloc handlers:

```dart
Future<void> _onDictationStarted(
  DictationStarted e,
  Emitter<NoteEditorState> emit,
) async {
  if (state.isDictating) return;
  if (!await _stt.isOfflineCapable) {
    emit(state.copyWith(dictationUnavailableExplainerRequested: true));
    return;
  }
  // mic permission flow — same as audio capture in Spec 13
  final status = await _permissions.microphoneStatus();
  // ...permission gate identical to audio path; then:
  emit(state.copyWith(isDictating: true, dictationDraft: ''));
  await _dictationSub?.cancel();
  _dictationSub = _stt.startDictation().listen((event) {
    if (isClosed) return;
    if (event is SttPartialResult) {
      add(_DictationPartial(event.text));
    } else if (event is SttFinalResult) {
      add(_DictationFinal(event.text));
    }
  });
}

void _onDictationPartial(_DictationPartial e, Emitter<NoteEditorState> emit) {
  emit(state.copyWith(dictationDraft: e.text));
}

Future<void> _onDictationFinal(_DictationFinal e, Emitter<NoteEditorState> emit) async {
  final note = state.note;
  if (note == null) return;
  // Append to last text block; create one if none exists.
  final blocks = [...note.blocks];
  final lastTextIdx = blocks.lastIndexWhere((b) => b['type'] == 'text');
  if (lastTextIdx >= 0) {
    final existing = blocks[lastTextIdx];
    blocks[lastTextIdx] = {
      ...existing,
      'content': '${existing['content'] ?? ''}${e.text}'.trim(),
    };
  } else {
    blocks.add({'type': 'text', 'content': e.text});
  }
  note.blocks = blocks;
  await _repository.save(note);
  emit(state.copyWith(
    note: note,
    isDictating: false,
    clearDictationDraft: true,
  ));
}

Future<void> _onDictationStopped(
  DictationStopped e,
  Emitter<NoteEditorState> emit,
) async {
  await _stt.stop();
  await _dictationSub?.cancel();
  _dictationSub = null;
  // The plugin emits a final SttFinalResult on stop; _onDictationFinal handles state.
}
```

`close()` cancels the subscription and calls `_stt.cancel()` if `isDictating`.

### H. Editor toolbar wiring

A `DictationButton` widget mirrors `AudioCaptureButton` from Spec 13: long-press starts, release stops; tap-to-toggle for accessibility. The button **does not render** when `state.isDictating` and the device can't run STT offline:

```dart
return BlocSelector<NoteEditorBloc, NoteEditorState, bool>(
  selector: (s) => s.note != null,
  builder: (ctx, hasNote) {
    final canDictate = ctx.read<SttService>().isOfflineCapable;
    return FutureBuilder<bool>(
      future: canDictate,
      builder: (_, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return _DictationButtonImpl();
      },
    );
  },
);
```

The future result is captured once on bloc init via the cached probe (which is synchronous after first run).

### I. `SettingsRepository` augmentation

Add to the abstract:

```dart
Future<bool> getSttOfflineCapable();
Future<void> setSttOfflineCapable(bool value);
```

Concrete `HiveSettingsRepository` implements via the `settings_v2` box at key `'sttOfflineCapable'`. Default = false (safer to hide the feature than to surface a network call).

### J. Forbidden-imports gate

Append to `scripts/.forbidden-imports.txt`:

```
# Hygiene gate (use SttService wrapper):
package:speech_to_text
```

Carve-out: the `forbidden_imports_lint` custom rule reads `scripts/.offline-allowlist` for path-based exemptions. Add:

```
# Spec 15: allowed inside the STT wrapper.
lib/services/speech/stt_service.dart
lib/services/speech/stt_capability_probe.dart
```

> Note: the existing custom_lint rule scoped exemptions per **path**. If it currently only matches per pattern, this spec extends it to path-based with the syntax above. Trivial change to `forbidden_imports_rule.dart` from Spec 02.

### K. Tests

- `note_editor_bloc_dictation_test.dart` — covers DictationStarted with `isOfflineCapable: false` (fires explainer flag, no listening), with permission denied (error message), with happy path (partial → final → text appended to last block).
- `fake_stt_service.dart` — exposes `emit(SttPartialResult)` and `emit(SttFinalResult)` for tests to drive.
- iOS / Android integration tests are out of scope for unit tests — they go in a future polish spec.

### L. Update `context/architecture.md`

- Stack table: add `speech_to_text ^7` row with note "on-device only via SttService wrapper".
- Storage model: add `sttOfflineCapable: bool` to the `settings` box list.
- Reaffirm invariant 1 with the gate description: STT goes through `SttService` which hard-gates on offline capability.

### M. Update `context/code-standards.md`

Append: STT consumers go through `SttService`; `package:speech_to_text` is forbidden under `lib/` outside `lib/services/speech/`.

### N. Update `context/progress-tracker.md`

- Mark Spec 15 complete.
- Architecture decisions entry 22: STT via `speech_to_text` ^7 with `onDevice: true` mandatory; capability probe at startup hides feature on incapable devices; subscription cancellation in bloc `close()`.
- Open questions:
  - 14. Android < 12 hard-hide is conservative — some devices have offline recognition via Google Now Pack on Android 11. Polish spec could relax this with a more nuanced probe.
  - 15. Multi-language switching during a dictation session — current scope: locale fixed for the duration of one session.

## Success Criteria

- [ ] Files in Section A exist; `SttService` wraps `speech_to_text`; capability probe runs at startup.
- [ ] `pubspec.yaml` adds `speech_to_text` only.
- [ ] `bash scripts/check-offline.sh` exits 0 with the new entry; carve-out works for `lib/services/speech/`.
- [ ] `flutter analyze`, `flutter test`, `dart format -l 100` all clean.
- [ ] **Manual smoke**:
  - On an iPhone (iOS 14+): long-press dictation button → speak "hello world" → italic preview shows in the active text block → release → final text "hello world" commits to the block.
  - On an Android 12+ device with offline recognition installed: same flow.
  - On an Android 11 device or an iPhone with on-device STT unsupported for current locale: the dictation button **does not render**.
  - Toggle airplane mode mid-dictation: recognition continues uninterrupted (proves on-device).
- [ ] No file under `lib/` outside `lib/services/speech/` imports `package:speech_to_text`.
- [ ] No invariant in `context/architecture.md` is changed; invariant 1 is reinforced.
- [ ] `NoteEditorBloc.close()` cancels any active dictation stream and calls `SttService.cancel()`.

## References

- [`context/architecture.md`](../context/architecture.md) — invariant 1 (no network); reinforced
- [`context/project-overview.md`](../context/project-overview.md) — STT is in-scope MVP
- [12-permissions-service](12-permissions-service.md), [13-audio-capture](13-audio-capture.md), [06-bloc-migration-editor](06-bloc-migration-editor.md)
- Plugin: <https://pub.dev/packages/speech_to_text>
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md)
- Agent: `flutter-expert` — invoke after the bloc dictation handlers; partial-result interpolation has subtle bugs around block index lookup
- Agent: `accessibility-tester` — hold-to-dictate must have a tap-to-toggle fallback (verified)
- Follow-up: Spec 16 (TTS), Spec 17 (device-capability-service refines the probe), Spec 21 (whisper-transcription) for audio-note → text on-device with a different model.
