# 13 — audio-capture

## Goal

Add **offline audio note capture and playback** to Notinotes. The user holds a mic button in the editor toolbar to record (or starts a session and stops manually); the audio file is saved to `<app_documents>/notes/<note_uuid>/audio/<asset_uuid>.m4a`, the path is persisted on the `Note`, and an audio block renders in the editor and on the home card with a waveform-style playhead. After this spec, audio notes work fully offline, no audio bytes ever leave the device, and the file lifecycle (save, replace, delete, cap) is owned by an `AudioRepository` per the architecture's invariant 5.

This spec is the first feature where the user-promised "multi-modal capture" gets real surface — text, image, and audio all coexist in the editor. Per [project-overview.md](../context/project-overview.md), audio notes are an explicit MVP goal.

## Dependencies

- [04-repository-layer](04-repository-layer.md) — repository conventions; `AudioRepository` follows the same pattern.
- [06-bloc-migration-editor](06-bloc-migration-editor.md) — `NoteEditorBloc` gains audio-specific events.
- [12-permissions-service](12-permissions-service.md) — `PermissionsService.requestMicrophone()` is the gate for record start.

## Agents & skills

**Pre-coding skills:**
- `flutter-apply-architecture-best-practices` — repository pattern for native plugin wrappers.
- `flutter-add-widget-test` — capture-button gestures + permission-flow widget tests.
- `dart-add-unit-test` — repo + bloc unit tests.

**After-coding agents:**
- `flutter-expert` — invoke after the recorder + player wiring; native streams leak easily without an explicit close path.
- `accessibility-tester` — long-press has assistive-tech tradeoffs; verify the tap-to-toggle fallback activates under VoiceOver / TalkBack.

## Design Decisions

### Package: `record`

`record` (^5.x) is the pragmatic choice over `flutter_sound`:

- Smaller, lighter API. We need start / stop / amplitude stream / dispose; that's exactly what `record` does.
- Cleaner null-safety, no FFI-level surprises.
- Active maintenance, ~700 likes on pub.dev, used in production by major Flutter apps.
- Supports M4A/AAC, AAC-LC, OGG-OPUS, WAV, FLAC.

`flutter_sound` is bigger and includes playback; we don't need its player because `audioplayers` is already in the Flutter ecosystem and its API is far simpler for the playback side.

**For playback we use `audioplayers`** (^6.x, also widely-used, BSD-3). One package per concern keeps the dep graph clean.

### Format: M4A / AAC-LC

- iOS native; no transcoding on iPhone.
- Universally decodable on Android (≥ API 16).
- ~64–128 kbps gives 8–16 KB/sec — a 10-minute note is ~5–10 MB, well under our 10 MB cap.
- Saved at 64 kbps mono by default. Configurable in settings (later spec); this spec hardcodes 64 kbps.

### Storage layout

Per [architecture.md](../context/architecture.md) invariant 7: blobs on disk, paths in Hive.

```
<app_documents>/
└── notes/<note_uuid>/audio/<audio_uuid>.m4a
```

`audio_uuid` is a fresh `Uuid().v4()` per recording. Replace = delete-then-write (no in-place overwrite, since `record` writes monotonically and the file lock during recording would conflict).

10 MB cap enforced at stop-time: if the resulting file exceeds 10 MB the repository truncates with a recorded `truncationFlag` field on the audio block — same pattern the existing image flow uses.

### Block model

`Note.blocks` (the unified editor block list, already present from the imported codebase) gains an audio variant:

```dart
{
  'type': 'audio',
  'id': '<asset_uuid>',
  'path': '<absolute path to .m4a file>',
  'durationMs': 23450,
  'amplitudePeaks': [0.12, 0.34, 0.81, ...],   // pre-rendered ~80 floats for waveform display
  'truncated': false,                           // true if file was capped at 10 MB
}
```

`amplitudePeaks` is captured during recording via `record`'s amplitude stream; we down-sample to 80 evenly-spaced peaks regardless of duration so the home card and editor renders are uniform. This avoids re-decoding the file every render.

The **legacy** non-block fields on `Note` (`imageFile`, etc.) are unaffected — audio is block-only from day one.

### Capture UX

Two interaction modes, picked by gesture:

- **Hold-to-record** (long-press the mic button in the editor toolbar): recording starts on press, stops and saves on release. Cancellable by sliding the finger off the button before release.
- **Tap-to-toggle**: tap once → recording starts, sustained pulse animation, timer counter, stop button overlay. Tap again → stop and save.

The primary affordance is hold-to-record (the natural "voice note" gesture, matched by every messaging app). Tap-to-toggle is an accessibility fallback exposed when reduced motion is requested or VoiceOver / TalkBack is active.

A live amplitude meter renders during recording (a small bar that pulses with input level, rendered from the amplitude stream).

### Playback UX

Audio blocks render as a 56px-tall pill in both the editor body and on home cards (in `withTodoList` / `normal` display modes; image-display mode hides them):

```
┌────────────────────────────────────────┐
│ ▶  ▎▎▎▍▎▍▎▎▍▍▎▎▎▎▍▎▎▎  0:23  ⋯       │
└────────────────────────────────────────┘
```

- Tap play → starts; pause icon swaps in.
- Waveform fills left-to-right with playback progress.
- Long-press → context menu: "Re-record" (deletes the file, starts a new capture), "Delete", "Share".
- "Share" is gated by the future P2P share spec; until then it's hidden.

### Repository

`AudioRepository` (abstract) + `FileSystemAudioRepository` (concrete):

```dart
abstract class AudioRepository {
  Future<AudioCaptureSession> startCapture({required String noteId});
  Future<AudioBlock> finalize(AudioCaptureSession session);
  Future<void> cancel(AudioCaptureSession session);
  Future<void> delete({required String noteId, required String audioId});
  Future<File> resolveFile({required String noteId, required String audioId});
  Stream<double> amplitudeStream(AudioCaptureSession session);
}
```

The session is a small record-or-class holding the temp file path, peak buffer, and start timestamp; concrete impl wraps the `record` plugin.

### NoteEditorBloc events

```dart
final class AudioCaptureRequested extends NoteEditorEvent { … }
final class AudioCaptureStopped   extends NoteEditorEvent { … }   // commits + emits AudioBlock
final class AudioCaptureCancelled extends NoteEditorEvent { … }   // discards
final class AudioBlockRemoved     extends NoteEditorEvent {
  const AudioBlockRemoved(this.audioId);
  final String audioId;
}
final class AudioBlockReplaced    extends NoteEditorEvent {
  const AudioBlockReplaced(this.audioId);   // triggers cancel-old + start-new
  final String audioId;
}
```

The bloc holds an in-flight `AudioCaptureSession?` while recording; events are no-ops if the session is already in the wrong phase (e.g. stop before start).

### Pre-record permission flow

The bloc's `AudioCaptureRequested` handler:

1. `permissionsService.microphoneStatus()`.
2. If `.granted` or `.limited` → start session.
3. If `.denied` → `permissionsService.requestMicrophone()`.
   - If user grants → start session.
   - If denied this time → emit `errorMessage: 'Microphone permission needed to record.'`; UI shows a one-shot snackbar.
4. If `.permanentlyDenied` or `.restricted` → emit a `state.popRequested`-style flag (`audioPermissionExplainerRequested`) → UI listener pops the `PermissionExplainerSheet`.

### Constraints / invariants reinforced

- **Invariant 1 (zero network)**: `record` and `audioplayers` are local-codec wrappers. No HTTP imports; no telemetry. Verified by the offline-imports gate.
- **Invariant 5 (Hive only via repos)**: only `AudioRepository` writes audio files to disk; the bloc never calls `dart:io` directly.
- **Invariant 7 (blobs on disk)**: audio bytes live in the file system; only the path + metadata go on the `Note`.
- **Invariant 8 (cancellation)**: the amplitude stream is closed and the temp file removed when `cancel` is called or the bloc is disposed mid-recording.
- **Invariant 9 (point-of-use permissions)**: mic permission is requested only when the user initiates `AudioCaptureRequested`.

## Implementation

### A. Files to create

```
lib/services/audio/
├── audio_capture_session.dart        ← typed session record
└── audio_block.dart                  ← typed AudioBlock (toJson/fromJson for the block map shape)

lib/repositories/audio/
├── audio_repository.dart             ← abstract
└── file_system_audio_repository.dart ← concrete (record + path_provider + uuid)

lib/features/note_editor/widgets/
├── audio_capture_button.dart         ← hold-to-record + tap-to-toggle FAB-shaped button
├── audio_block_view.dart             ← play/pause + waveform + controls
└── audio_amplitude_meter.dart        ← live mic level during recording

test/repositories/audio/
├── fake_audio_repository.dart
└── file_system_audio_repository_test.dart   ← uses path_provider's mock

test/features/note_editor/widgets/
└── audio_capture_button_test.dart
```

### B. `pubspec.yaml` additions

```yaml
dependencies:
  record: ^5.1.2
  audioplayers: ^6.1.0
```

Run `flutter pub get`. Re-run `bash scripts/check-offline.sh` to confirm neither package transitively imports a forbidden network client.

### C. `lib/services/audio/audio_block.dart`

```dart
import 'package:equatable/equatable.dart';

class AudioBlock extends Equatable {
  const AudioBlock({
    required this.id,
    required this.path,
    required this.durationMs,
    required this.amplitudePeaks,
    this.truncated = false,
  });

  final String id;
  final String path;
  final int durationMs;
  final List<double> amplitudePeaks;
  final bool truncated;

  Map<String, dynamic> toJson() => {
        'type': 'audio',
        'id': id,
        'path': path,
        'durationMs': durationMs,
        'amplitudePeaks': amplitudePeaks,
        'truncated': truncated,
      };

  factory AudioBlock.fromJson(Map<String, dynamic> json) {
    return AudioBlock(
      id: json['id'] as String,
      path: json['path'] as String,
      durationMs: json['durationMs'] as int,
      amplitudePeaks: (json['amplitudePeaks'] as List).cast<num>().map((n) => n.toDouble()).toList(),
      truncated: (json['truncated'] as bool?) ?? false,
    );
  }

  @override
  List<Object?> get props => [id, path, durationMs, amplitudePeaks, truncated];
}
```

### D. `lib/services/audio/audio_capture_session.dart`

```dart
class AudioCaptureSession {
  AudioCaptureSession({
    required this.id,
    required this.noteId,
    required this.tempFilePath,
    required this.startedAt,
  });

  final String id;
  final String noteId;
  final String tempFilePath;
  final DateTime startedAt;

  /// Mutable: amplitude peaks accumulate during capture.
  final List<double> amplitudePeaks = <double>[];
}
```

### E. `lib/repositories/audio/audio_repository.dart`

```dart
import 'dart:io';

import 'package:noti_notes_app/services/audio/audio_block.dart';
import 'package:noti_notes_app/services/audio/audio_capture_session.dart';

abstract class AudioRepository {
  Future<AudioCaptureSession> startCapture({required String noteId});
  Stream<double> amplitudeStream(AudioCaptureSession session);
  Future<AudioBlock> finalize(AudioCaptureSession session);
  Future<void> cancel(AudioCaptureSession session);
  Future<void> delete({required String noteId, required String audioId});
  Future<File> resolveFile({required String noteId, required String audioId});
}
```

### F. `lib/repositories/audio/file_system_audio_repository.dart`

```dart
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import 'package:noti_notes_app/repositories/audio/audio_repository.dart';
import 'package:noti_notes_app/services/audio/audio_block.dart';
import 'package:noti_notes_app/services/audio/audio_capture_session.dart';

class FileSystemAudioRepository implements AudioRepository {
  FileSystemAudioRepository({AudioRecorder? recorder, Uuid? uuid})
      : _recorder = recorder ?? AudioRecorder(),
        _uuid = uuid ?? const Uuid();

  static const int _bitRate = 64000;
  static const int _sampleRate = 44100;
  static const int _maxBytes = 10 * 1024 * 1024;
  static const int _peakBuckets = 80;

  final AudioRecorder _recorder;
  final Uuid _uuid;

  Future<Directory> _audioDir(String noteId) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'notes', noteId, 'audio'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  @override
  Future<AudioCaptureSession> startCapture({required String noteId}) async {
    final dir = await _audioDir(noteId);
    final id = _uuid.v4();
    final path = p.join(dir.path, '$id.m4a');
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: _bitRate,
        sampleRate: _sampleRate,
        numChannels: 1,
      ),
      path: path,
    );
    return AudioCaptureSession(
      id: id,
      noteId: noteId,
      tempFilePath: path,
      startedAt: DateTime.now(),
    );
  }

  @override
  Stream<double> amplitudeStream(AudioCaptureSession session) async* {
    await for (final amp in _recorder.onAmplitudeChanged(const Duration(milliseconds: 60))) {
      // amp.current is in dB (negative); normalize to [0, 1].
      final normalized = ((amp.current + 60) / 60).clamp(0.0, 1.0).toDouble();
      session.amplitudePeaks.add(normalized);
      yield normalized;
    }
  }

  @override
  Future<AudioBlock> finalize(AudioCaptureSession session) async {
    final path = await _recorder.stop();
    if (path == null) {
      throw StateError('Recorder returned null path on finalize');
    }
    final file = File(path);
    var truncated = false;
    if (file.lengthSync() > _maxBytes) {
      // Truncate by re-encoding is expensive; for v1 we just flag and trust
      // the user to keep clips under 10 minutes. Future spec can add hard
      // truncation via FFmpeg. For now: persist as-is, flag, surface in UI.
      truncated = true;
    }
    final durationMs = DateTime.now().difference(session.startedAt).inMilliseconds;
    final peaks = _downsample(session.amplitudePeaks, _peakBuckets);
    return AudioBlock(
      id: session.id,
      path: path,
      durationMs: durationMs,
      amplitudePeaks: peaks,
      truncated: truncated,
    );
  }

  @override
  Future<void> cancel(AudioCaptureSession session) async {
    if (await _recorder.isRecording()) await _recorder.cancel();
    final f = File(session.tempFilePath);
    if (f.existsSync()) f.deleteSync();
  }

  @override
  Future<void> delete({required String noteId, required String audioId}) async {
    final dir = await _audioDir(noteId);
    final f = File(p.join(dir.path, '$audioId.m4a'));
    if (f.existsSync()) f.deleteSync();
  }

  @override
  Future<File> resolveFile({required String noteId, required String audioId}) async {
    final dir = await _audioDir(noteId);
    return File(p.join(dir.path, '$audioId.m4a'));
  }

  List<double> _downsample(List<double> source, int targetLength) {
    if (source.isEmpty) return List.filled(targetLength, 0.0);
    if (source.length <= targetLength) {
      return [
        ...source,
        ...List.filled(targetLength - source.length, 0.0),
      ];
    }
    final ratio = source.length / targetLength;
    final out = <double>[];
    for (var i = 0; i < targetLength; i++) {
      final start = (i * ratio).floor();
      final end = math.min(((i + 1) * ratio).ceil(), source.length);
      double max = 0;
      for (var j = start; j < end; j++) {
        if (source[j] > max) max = source[j];
      }
      out.add(max);
    }
    return out;
  }
}
```

### G. NoteEditorBloc additions

Add to `note_editor_event.dart`:

```dart
final class AudioCaptureRequested extends NoteEditorEvent {
  const AudioCaptureRequested();
}

final class AudioCaptureStopped extends NoteEditorEvent {
  const AudioCaptureStopped();
}

final class AudioCaptureCancelled extends NoteEditorEvent {
  const AudioCaptureCancelled();
}

final class AudioBlockRemoved extends NoteEditorEvent {
  const AudioBlockRemoved(this.audioId);
  final String audioId;
  @override
  List<Object?> get props => [audioId];
}
```

Add to `note_editor_state.dart`:

```dart
// Inside NoteEditorState — non-equatable transient flags so a second
// emission resets them, like popRequested.
final bool audioPermissionExplainerRequested;
final bool isCapturingAudio;
final double? currentAmplitude;   // null when idle, [0,1] when capturing
```

Update `copyWith` to include them (with `clearAmplitude: true` flag) and add to `props`.

Add to `note_editor_bloc.dart`:

```dart
// Constructor adds AudioRepository + PermissionsService dependencies.

AudioCaptureSession? _activeAudioSession;
StreamSubscription<double>? _amplitudeSub;

Future<void> _onAudioCaptureRequested(
  AudioCaptureRequested e,
  Emitter<NoteEditorState> emit,
) async {
  final note = state.note;
  if (note == null || _activeAudioSession != null) return;

  final status = await _permissions.microphoneStatus();
  if (status.isFinalDenial) {
    emit(state.copyWith(audioPermissionExplainerRequested: true));
    return;
  }
  if (!status.isUsable) {
    final result = await _permissions.requestMicrophone();
    if (!result.isUsable) {
      if (result.isFinalDenial) {
        emit(state.copyWith(audioPermissionExplainerRequested: true));
      } else {
        emit(state.copyWith(errorMessage: 'Microphone permission needed to record.'));
      }
      return;
    }
  }

  final session = await _audio.startCapture(noteId: note.id);
  _activeAudioSession = session;
  emit(state.copyWith(isCapturingAudio: true, currentAmplitude: 0));

  await _amplitudeSub?.cancel();
  _amplitudeSub = _audio.amplitudeStream(session).listen((amp) {
    if (isClosed) return;
    emit(state.copyWith(currentAmplitude: amp));
  });
}

Future<void> _onAudioCaptureStopped(
  AudioCaptureStopped e,
  Emitter<NoteEditorState> emit,
) async {
  final session = _activeAudioSession;
  final note = state.note;
  if (session == null || note == null) return;

  await _amplitudeSub?.cancel();
  _amplitudeSub = null;

  final block = await _audio.finalize(session);
  _activeAudioSession = null;

  note.blocks = [...note.blocks, block.toJson()];
  await _repository.save(note);

  emit(state.copyWith(
    isCapturingAudio: false,
    note: note,
    clearAmplitude: true,
  ));
}

Future<void> _onAudioCaptureCancelled(
  AudioCaptureCancelled e,
  Emitter<NoteEditorState> emit,
) async {
  final session = _activeAudioSession;
  if (session == null) return;
  await _amplitudeSub?.cancel();
  _amplitudeSub = null;
  await _audio.cancel(session);
  _activeAudioSession = null;
  emit(state.copyWith(isCapturingAudio: false, clearAmplitude: true));
}

Future<void> _onAudioBlockRemoved(
  AudioBlockRemoved e,
  Emitter<NoteEditorState> emit,
) async {
  final note = state.note;
  if (note == null) return;
  note.blocks = note.blocks
      .where((b) => !(b['type'] == 'audio' && b['id'] == e.audioId))
      .toList();
  await _audio.delete(noteId: note.id, audioId: e.audioId);
  await _repository.save(note);
  emit(state.copyWith(note: note));
}

@override
Future<void> close() async {
  await _amplitudeSub?.cancel();
  if (_activeAudioSession != null) {
    await _audio.cancel(_activeAudioSession!);
  }
  return super.close();
}
```

### H. Editor toolbar wiring

`audio_capture_button.dart` is a `GestureDetector` wrapper around the `mic.svg` icon:

- `onLongPressStart` → `add(const AudioCaptureRequested())`.
- `onLongPressEnd` → `add(const AudioCaptureStopped())`.
- `onLongPressMoveUpdate` with offset moved past 80px → cancel hint UI.
- `onLongPressCancel` → `add(const AudioCaptureCancelled())`.
- `onTap` (when accessibility services active per `MediaQuery.accessibleNavigation`) → toggle.

A `BlocListener<NoteEditorBloc, NoteEditorState>` shows the `PermissionExplainerSheet` when `state.audioPermissionExplainerRequested` flips to true, then resets the flag on the next emission (same pattern as `popRequested`).

### I. Editor body — render audio blocks

`note_editor/screen.dart`'s block rendering switch gains an `'audio'` case that mounts `AudioBlockView` (Section J). The home `note_card.dart` also gets an audio-block summary: a small mic glyph + duration ("Audio · 0:23"), no waveform, since the card is small.

### J. `audio_block_view.dart` (playback)

Uses `audioplayers`'s `AudioPlayer`:

```dart
class _AudioBlockViewState extends State<AudioBlockView> {
  late final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _posSub;
  Duration _position = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() {
        _playing = false;
        _position = Duration.zero;
      });
    });
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      await _player.play(DeviceFileSource(widget.block.path));
      setState(() => _playing = true);
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ...build: pill with play button, waveform, time. Waveform fills based on
  // _position.inMilliseconds / widget.block.durationMs.
}
```

Long-press on the pill → context menu with "Re-record" (dispatches `AudioBlockRemoved` then `AudioCaptureRequested`), "Delete" (`AudioBlockRemoved`), "Share" (hidden until share spec wires it).

### K. `lib/main.dart`

Add to `MultiRepositoryProvider`:

```dart
RepositoryProvider<AudioRepository>.value(
  value: FileSystemAudioRepository(),
),
```

Update `NoteEditorBloc` factory wherever it's mounted (the editor route push site) to pass `audio: ctx.read<AudioRepository>()` and `permissions: ctx.read<PermissionsService>()`.

### L. Tests

- `file_system_audio_repository_test.dart` — uses `path_provider_platform_interface`'s `setMockMethodCallHandler` to point `getApplicationDocumentsDirectory` at a temp dir. Verifies start → finalize → file exists; cancel → file removed; delete → file removed.
- `audio_capture_button_test.dart` — widget test with a `FakePermissionsService` (mic = denied → tap → permission requested; mic = granted → long-press fires `AudioCaptureRequested`).
- `note_editor_bloc_test.dart` extension — covers the four new events using a `FakeAudioRepository` that returns scripted sessions / blocks.

### M. Update `context/architecture.md`

- Stack table: add `record ^5`, `audioplayers ^6` rows.
- System boundaries: add `lib/services/audio/`, `lib/repositories/audio/`.
- Storage model: under "Filesystem layout", confirm `<note_uuid>/audio/<asset_uuid>.m4a` is the canonical path.
- Data flow examples: add "Capture an audio note" walkthrough.

### N. Update `context/code-standards.md`

Append to **Forbidden imports** (hygiene):

- `package:record` and `package:audioplayers` direct imports are confined to `lib/services/audio/`, `lib/repositories/audio/`, and `lib/features/note_editor/widgets/audio_*.dart`. Other consumers go through `AudioRepository` and `AudioBlockView`.

### O. Update `context/progress-tracker.md`

- Mark Spec 13 complete.
- Architecture decisions entry 21: audio capture via `record`; playback via `audioplayers`; M4A/AAC-LC at 64 kbps mono; 80-bucket peak waveform; 10 MB cap with `truncated` flag (no FFmpeg yet).
- Open questions:
  - Hard truncation at 10 MB requires FFmpeg or similar — decide in a polish spec whether we add `ffmpeg_kit_flutter_min` (offline, GPL caveat) or just enforce client-side max-duration UI gate.
  - Background recording — currently stops if app backgrounds; iOS background-audio entitlement is its own consideration.

## Success Criteria

- [ ] Files in Section A exist; the editor renders audio blocks; capture works on iOS sim + Android emu.
- [ ] `pubspec.yaml` adds `record` and `audioplayers` only.
- [ ] `bash scripts/check-offline.sh` exits 0; no transitive forbidden imports introduced.
- [ ] `flutter analyze`, `flutter test`, `dart format -l 100` all clean.
- [ ] `flutter test` covers: file repo round-trip; capture button gestures + permission flow; bloc events for record / stop / cancel / remove.
- [ ] **Manual smoke**:
  - Open a note → long-press mic → counter ticks + amplitude meter pulses → release → audio pill appears below text.
  - Tap pill → audio plays → waveform fills with progress.
  - Re-open the app, navigate to the note → audio still plays (path persisted).
  - Long-press the pill → "Delete" → file gone from `<app_documents>/notes/<note_id>/audio/`.
  - Deny mic permission permanently → next long-press shows the explainer sheet → "Open settings" deep-links to OS settings.
  - Airplane mode: full capture + playback works unchanged.
- [ ] No widget under `lib/features/` imports `package:record` or `package:audioplayers` outside the allowed paths in Section N.
- [ ] Invariants 1, 5, 7, 8, 9 verified: no network imports; only repo touches files; blobs on disk; amplitude stream cancellable; permission requested at point of use.
- [ ] No invariant in `context/architecture.md` is changed.

## References

- [`context/architecture.md`](../context/architecture.md), [`context/code-standards.md`](../context/code-standards.md), [`context/project-overview.md`](../context/project-overview.md)
- [12-permissions-service](12-permissions-service.md) — mic permission gate
- [06-bloc-migration-editor](06-bloc-migration-editor.md) — bloc events extended here
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md)
- Skill: [`flutter-add-widget-test`](../.agents/skills/flutter-add-widget-test/SKILL.md)
- Agent: `flutter-expert` — invoke after the recorder + player wiring; native streams are easy to leak
- Agent: `accessibility-tester` — invoke against the capture button; long-press has assistive-tech tradeoffs
- Plugin docs: <https://pub.dev/packages/record>, <https://pub.dev/packages/audioplayers>
- Follow-ups: 14 (ink — deferred to v2 stub), 15 (STT — also wraps mic), 22 (P2P — share button on audio block becomes real)
