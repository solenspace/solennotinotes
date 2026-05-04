# Notinotes — Architecture

## Stack

| Layer | Tech | Role |
|-------|------|------|
| App framework | Flutter 3.x (Dart 3) | Cross-platform iOS + Android UI |
| Material | Material 3 | Component baseline |
| State | `flutter_bloc` 9.x | Business logic separation, BLoC + Cubit |
| Local DB | `hive_ce` + `hive_ce_flutter` 2.x | Notes, tags, themes, settings, received inbox |
| Code gen | `build_runner` | Hive adapters, freezed (introduce per spec), json_serializable |
| File storage | `path_provider` | App documents dir for blobs (audio + image) |
| Localization | `intl` 0.20 | ARB-driven; English-only at MVP |
| Reminders | `flutter_local_notifications` + `timezone` + `flutter_timezone` | Local OS notifications (no push server) |
| Permissions | `permission_handler` | Runtime requests at point of use |
| Image capture | `image_picker` + `flutter_image_compress` | Camera/gallery + size cap |
| Audio capture | TBD per spec | Voice notes (offline-only) |
| P2P transport | `flutter_nearby_connections` | Apple Multipeer + Android Nearby Connections; messages, bytes, files |
| STT | `speech_to_text` | Native dictation; offline where the device supports it |
| TTS | `flutter_tts` | Native text-to-speech; fully offline |
| On-device LLM | `fllama` (llama.cpp + GGUF) — to validate per spec | Summarize, rewrite, suggest titles |
| On-device whisper | TBD per spec (whisper.cpp binding) | Audio note → text transcription |
| Device capability | `device_info_plus` | Gate AI features by RAM / OS version |
| Routing | `go_router` (introduce per spec) | Declarative routing |
| Icons / assets | `flutter_svg`, custom SF Pro Display fonts, pattern PNGs | Existing assets stay |

Existing dependencies (`provider`, `flutter_staggered_grid_view`, `material_tag_editor`, `animations`, `flutter_animate`, `google_fonts`, `gap`, `board_datetime_picker`, `string_similarity`, `uuid`, `collection`) remain until specs explicitly migrate them.

## System boundaries

```
lib/
├── main.dart                  ← app entry; bootstraps Hive, providers, routing
├── app/                       ← MaterialApp, theme glue, route table, global providers
├── features/<feature>/        ← collocated feature unit
│   ├── bloc/                  ← BLoCs / Cubits for the feature; no widget imports
│   ├── repository/            ← Hive + filesystem + native-plugin wrappers for the feature
│   ├── widgets/               ← UI components used only by this feature
│   ├── screen.dart            ← single-screen feature (or screens/ if multiple)
│   └── legacy/                ← Provider-based code in transition; retired in Spec 05+
├── services/                  ← cross-cutting native wrappers (STT, TTS, P2P, AI, permissions, notifications, image)
├── models/                    ← immutable domain models shared across features
├── theme/                     ← base ThemeData + NotiTheme overlay system
├── helpers/                   ← stateless utilities (validators, formatters)
├── widgets/                   ← shared widgets used by 2+ features
└── assets/                    ← icons, fonts, pattern images (frozen)
```

Provider-based files inherited from the imported codebase live under `features/<feature>/legacy/` until Specs 05+ migrate them to `flutter_bloc` and Spec 08 deletes the `legacy/` folders.

## Storage model

### Hive boxes (typed, with adapters)
- `notes` — primary note records keyed by uuid
- `tags` — tag definitions (name, color)
- `themes` — saved NotiTheme presets
- `noti_identity` — single record: this user's noti (name, signature, palette, pattern, generated keypair for share signing)
- `settings` — app-level preferences
- `received_inbox` — incoming shares awaiting accept/discard

### Filesystem layout
```
<app_documents>/
└── notes/
    └── <note_uuid>/
        ├── images/<asset_uuid>.jpg     ← compressed via flutter_image_compress
        └── audio/<asset_uuid>.m4a      ← capped at 10 MB; truncation flag in Hive metadata
```

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
9. **Permissions requested at point of use** (mic when starting recording; camera when opening capture; BLE when opening share). Not at startup.
10. **AI model files live in app support directory**, downloaded on first AI use, never bundled in the IPA/APK.
11. **P2P payloads size-capped to 50 MB** and chunked. Receiver shows progress; either side can cancel.
12. **Sender's NotiIdentity ships with every shared note** so the receiver renders it faithfully.

## Data flow examples

### Save a text note
`NoteEditorScreen` → dispatches `SaveNoteRequested` → `NoteEditorBloc` → `NoteRepository.save(note)` → `HiveDataSource` writes to `notes` box → emits `NoteSaved` → screen pops or shows confirmation.

### Receive a shared note
`SharePeerService` (P2P transport) emits `IncomingPayload(bytes)` → `ShareInboxBloc` decodes manifest → validates signature → writes assets to disk → inserts a record into `received_inbox` Hive box → UI reflects the new inbox count → user opens preview → on accept, `ShareInboxBloc` calls `NoteRepository.importFromShare(...)` to merge.

### On-device AI summarize
`NoteScreen` → `AiAssistBloc` checks `DeviceCapabilityService.canRunSmallLlm()` → if true, calls `LlmService.summarize(noteText)` → service streams tokens from local llama.cpp runtime → BLoC emits `AssistResultStreaming(token)` → screen appends to a draft → on completion the user accepts/rejects.
