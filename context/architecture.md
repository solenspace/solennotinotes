# Notinotes — Architecture

## Stack

| Layer | Tech | Role |
|-------|------|------|
| App framework | Flutter 3.x (Dart 3) | Cross-platform iOS + Android UI |
| Material | Material 3 | Component baseline |
| State | `flutter_bloc` 9.x | Business logic separation, BLoC + Cubit. `package:provider` removed in Spec 10. |
| Theme tokens | `lib/theme/tokens/` two-layer system | Raw primitives → semantic `ThemeExtension`s consumed via `context.tokens.<category>.<role>`. Per-note overlays (Spec 11) patch `NotiColors` / `NotiPatternBackdrop` / `NotiSignature`. |
| Local DB | `hive_ce` + `hive_ce_flutter` 2.x | Notes, tags, themes, settings, received inbox |
| Code gen | `build_runner` | Hive adapters, freezed (introduce per spec), json_serializable |
| File storage | `path_provider` | App documents dir for blobs (audio + image) |
| Localization | `intl` 0.20 | ARB-driven; English-only at MVP |
| Reminders | `flutter_local_notifications` + `timezone` + `flutter_timezone` | Local OS notifications (no push server) |
| Permissions | `permission_handler` 12.x via `PermissionsService` wrapper | Point-of-use permission orchestration; consumers receive a typed `PermissionResult`, never raw plugin output |
| Image capture | `image_picker` + `flutter_image_compress` | Camera/gallery + size cap |
| Audio capture | `record` 5.x | M4A/AAC-LC at 64 kbps mono; amplitude stream feeds the live meter and the pre-rendered waveform |
| Audio playback | `audioplayers` 6.x | `DeviceFileSource` playback for audio blocks; offline-only |
| P2P transport | `flutter_nearby_connections` | Apple Multipeer + Android Nearby Connections; messages, bytes, files |
| STT | `speech_to_text` 7.x via `SttService` wrapper | Native dictation, `onDevice: true` enforced on every recognition request; cold-start `SttCapabilityProbe` caches `sttOfflineCapable: bool` in `settings_v2`, dictation UI hides itself when the probe returns false (Spec 15) |
| TTS | `flutter_tts` | Native text-to-speech; fully offline |
| On-device LLM | `fllama` (llama.cpp + GGUF) — to validate per spec | Summarize, rewrite, suggest titles |
| On-device whisper | TBD per spec (whisper.cpp binding) | Audio note → text transcription |
| Device capability | `device_info_plus` | Gate AI features by RAM / OS version |
| Routing | `go_router` (introduce per spec) | Declarative routing |
| Icons / assets | `flutter_svg`, custom SF Pro Display fonts, pattern PNGs | Existing assets stay |

Existing dependencies (`flutter_staggered_grid_view`, `material_tag_editor`, `animations`, `flutter_animate`, `google_fonts`, `gap`, `board_datetime_picker`, `string_similarity`, `uuid`, `collection`) remain until specs explicitly migrate them. `package:provider` was removed in Spec 10 and is now in `scripts/.forbidden-imports.txt`.

## System boundaries

```
lib/
├── main.dart                  ← app entry; bootstraps Hive, providers, routing
├── app/                       ← MaterialApp, theme glue, route table, global providers
├── features/<feature>/        ← collocated feature unit
│   ├── bloc/                  ← BLoCs / Cubits for the feature; no widget imports
│   ├── repository/            ← feature-private data, only this feature reads/writes
│   ├── widgets/               ← UI components used only by this feature
│   ├── screen.dart            ← single-screen feature (or screens/ if multiple)
│   └── legacy/                ← Provider-based code in transition; retired in Spec 05+
├── repositories/<resource>/   ← cross-cutting domain data (Note, Tag, Theme, NotiIdentity, …)
├── services/                  ← cross-cutting native wrappers (STT, TTS, P2P, AI, permissions, notifications, image)
├── models/                    ← immutable domain models shared across features
├── theme/                     ← base ThemeData + NotiTheme overlay system
├── helpers/                   ← stateless utilities (validators, formatters)
├── widgets/                   ← shared widgets used by 2+ features
└── assets/                    ← icons, fonts, pattern images (frozen)
```

Provider-based files inherited from the imported codebase live under `features/<feature>/legacy/` until Specs 05+ migrate them to `flutter_bloc` and Spec 08 deletes the `legacy/` folders.

A **cross-cutting repository** (under `lib/repositories/<resource>/`) owns a domain resource that is consumed by two or more features (e.g. `Note` is read by home, note_editor, search, and the future share flow). A **feature-private repository** (under `lib/features/<feature>/repository/`) is consumed only by its parent feature. When in doubt, start feature-private and promote to cross-cutting if a second feature needs to read it.

## Storage model

### Hive boxes (typed, with adapters)
- `notes` — primary note records keyed by uuid
- `tags` — tag definitions (name, color)
- `themes` — saved NotiTheme presets
- `noti_identity` — single record: this user's noti (id, displayName, bornDate, profilePicture, signaturePalette, signaturePatternKey, signatureAccent, signatureTagline). Migrated from legacy `user_v2` on first launch after Spec 09. Cryptographic keypair for share-payload signing is added by the future P2P share spec.
- `settings` — app-level preferences (themeMode, writingFont, plus the `sttOfflineCapable: bool` capability cache written by Spec 15's startup probe)
- `received_inbox` — incoming shares awaiting accept/discard

### Filesystem layout
```
<app_documents>/
└── notes/
    └── <note_uuid>/
        ├── images/<asset_uuid>.jpg     ← compressed via flutter_image_compress
        └── audio/<asset_uuid>.m4a      ← capped at 10 MB; truncation flag in Hive metadata
```

### Per-note overlay
Per-note overlay fields are currently scattered across `Note.{colorBackground, fontColor, patternImage, gradient, hasGradient}`. Spec 11's `Note.toOverlay()` extension synthesizes a `NotiThemeOverlay` from those fields; every editor render goes through it, and every overlay event handler writes back to the legacy fields for Hive-storage compatibility. Spec 04b retires the scattered fields in favor of a single `Note.overlay: NotiThemeOverlay` value with `signatureAccent`, `signatureTagline`, and `fromIdentityId` promoted to first-class columns.

### Share payload
- A zipped folder containing `manifest.json` (note + assets index + sender NotiIdentity) plus the asset files.
- Payload signed by the sender's noti keypair so the receiver can attribute it.
- Versioned with a `format_version` field at the manifest root for future evolution.

## Invariants (non-negotiable)

1. **Zero network in runtime.** No `package:http`, `package:dio`, `dart:io.HttpClient`, no cloud SDKs. CI grep blocks these imports.
2. **AI features are device-gated.** Every AI entry point checks `device_info_plus` against the configured RAM threshold; below it, the affordance does not render.
3. **P2P advertising/discovery is opt-in per session.** No background scanning, no auto-advertise on launch.
4. **Received notes land in `received_inbox` first.** Merging into the main library requires explicit user accept.
5. **Hive writes flow through repositories.** Screens, widgets, and BLoCs never call `box.put` directly.
6. **BLoCs do not import widgets. Widgets do not import repositories.** Dependency direction is strict.
7. **Audio + image blobs live on disk.** Hive stores file paths and metadata only — never the bytes.
8. **Every async stream and future has explicit cancellation.** `StreamSubscription.cancel()` in `close`/`dispose`; AI runs cancellable.
9. **Permissions requested at point of use** (mic when starting recording; camera when opening capture; BLE when opening share). Not at startup. Every consumer goes through `PermissionsService` (`lib/services/permissions/`); direct `package:permission_handler` imports under `lib/` are forbidden by code review (Spec 12).
10. **AI model files live in app support directory**, downloaded on first AI use, never bundled in the IPA/APK.
11. **P2P payloads size-capped to 50 MB** and chunked. Receiver shows progress; either side can cancel.
12. **Sender's NotiIdentity ships with every shared note** so the receiver renders it faithfully.

## Data flow examples

### Save a text note
`NoteEditorScreen` → BLoC (Spec 05) → `NotesRepository.save(note)` → `HiveNotesRepository` writes to `notes_v2` box (typed adapters land in Spec 04b) → `box.watch()` re-emits the snapshot → `watchAll()` consumers refresh.

### Load + render the home screen
`HomeScreen` mounts → `BlocProvider` creates `NotesListBloc` and dispatches `NotesListSubscribed` → BLoC subscribes to `repository.watchAll()` → `HiveNotesRepository` yields the current snapshot → BLoC emits `ready` state → `BlocBuilder` rebuilds the masonry grid via `state.pinnedNotes` / `state.unpinnedNotes`. Subsequent `repository.save(...)` / `repository.delete(...)` calls (from any feature) trigger re-emits via `box.watch()` → BLoC re-emits with the fresh list → grid rebuilds.

### Receive a shared note
`SharePeerService` (P2P transport) emits `IncomingPayload(bytes)` → `ShareInboxBloc` decodes manifest → validates signature → writes assets to disk → inserts a record into `received_inbox` Hive box → UI reflects the new inbox count → user opens preview → on accept, `ShareInboxBloc` calls `NoteRepository.importFromShare(...)` to merge.

### Open editor → render with the note's overlay
Route push mounts `NoteEditorBloc` → BLoC emits `ready` with the `Note` → editor `BlocBuilder` calls `note.toOverlay()` and patches `NotiColors` / `NotiPatternBackdrop` / `NotiSignature` via `overlay.applyTo*(...)` → wraps the body subtree in `AnimatedTheme(data: themed)` → `AppBar`, `Scaffold`, status bar, and any sheets opened from inside the route inherit the overlay → user pops the route → `AnimatedTheme` interpolates back to the base theme over `tokens.motion.pattern` (~720 ms).

### On-device AI summarize
`NoteScreen` → `AiAssistBloc` checks `DeviceCapabilityService.canRunSmallLlm()` → if true, calls `LlmService.summarize(noteText)` → service streams tokens from local llama.cpp runtime → BLoC emits `AssistResultStreaming(token)` → screen appends to a draft → on completion the user accepts/rejects.

### Capture an audio note
Editor toolbar mic long-press → `NoteEditorBloc._onAudioCaptureRequested` → `PermissionsService.microphoneStatus` (and `requestMicrophone` if not granted) → on success, `AudioRepository.startCapture(noteId)` opens a recorder writing to `<docs>/notes/<id>/audio/<uuid>.m4a` and returns an `AudioCaptureSession` → bloc subscribes to `amplitudeStream` and bridges samples through the synthetic `AudioAmplitudeSampled` event so each sample lands on the bloc's event loop (a direct `emit` from the listener would race with handler completion) → release fires `AudioCaptureStopped` → repository finalizes (downsamples to an 80-bucket waveform, applies the 10 MB cap as a `truncated` flag) → bloc emits a one-shot `committedAudioBlock` → screen consumes via `BlocListener`, appends to its local `_blocks` list, and dispatches `BlocksReplaced` → `NotesRepository.save` → `notes_v2` snapshot re-emits to the home grid. Bloc never mutates `note.blocks` directly; the screen owns block-list state, mirroring the image-block flow.

### Dictate into a text block
Editor toolbar dictation long-press → `NoteEditorBloc._onDictationStarted` → if `SttService.isOfflineCapable` is false, emits the one-shot `dictationUnavailableExplainerRequested` and returns → otherwise the same `PermissionsService` mic gate as audio capture → on success, subscribes to `SttService.startDictation(localeId)` (a `Stream<SttRecognitionEvent>`) and bridges each event through the synthetic `DictationPartialEmitted` / `DictationFinalEmitted` events (sealed switch) → `_onDictationPartialEmitted` updates `state.dictationDraft` for the in-flight italic preview banner → recognizer's terminal `SttFinalResult` (or user-driven `_onDictationStopped`) routes through `_onDictationFinalEmitted`, which emits the one-shot `committedDictationText` → screen's `_appendDictationText` mutates the last `TextBlock` (or appends a new one) and dispatches `BlocksReplaced`. Closing the bloc cancels the recognizer subscription and calls `SttService.cancel()` if listening (invariant 8). On no-text final results (silence timeout / empty utterance) the bloc clears state but does not surface the commit signal.
