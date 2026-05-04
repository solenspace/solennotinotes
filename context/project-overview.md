# Notinotes — Project Overview

## Product

Notinotes is an **offline-first, beautifully customizable** note-taking app for iOS and Android. Every user gets their own **"noti"** — a personal identity (theme palette, signature, name, accent pattern) that travels with every note they share, so when you receive a note from a friend it arrives wearing their look.

The app **never connects to the cloud**. Notes live on the device. Sharing happens **peer-to-peer over Bluetooth / Wi-Fi-Direct / Apple Multipeer** when two devices are physically near each other. There is no backend, no account, no server, no telemetry, no analytics.

AI assistance (summarize, rewrite, suggest titles, transcribe audio) runs **on-device** via a small quantized LLM (llama.cpp / GGUF) and on-device speech-to-text and text-to-speech. AI features gate themselves behind device capability detection and degrade silently on phones that cannot run the model.

## Goals

1. **Zero network calls in normal operation.** Airplane mode does not change behavior. Privacy by design.
2. **Multi-modal capture**: typed text, dictated text (STT), audio recording, camera/gallery image, freehand ink drawing, todos, tags.
3. **AI assist is on-device or absent.** Cloud LLM API calls are forbidden.
4. **Per-user "noti" identity.** Each install generates a noti (palette + pattern + name + signature). The noti is what makes a note feel personal and travels with shared notes.
5. **P2P share that's instant and complete.** When two phones are nearby, the receiver gets the full note: text, todos, images, audio, configuration, theme — exactly as the sender sees it.
6. **Beautiful by default and beautiful customized.** Every note can override the base theme with its own NotiTheme (colors, pattern background, font weight, accent).
7. **Scalable Flutter patterns.** flutter_bloc + repository layer + feature folders + immutable models + tested.

## Core flows

### Capture flow
1. Open quick-capture from home → choose modality (text · todo · image · audio · ink).
2. Compose; optional AI assist (`Summarize`, `Rewrite`, `Suggest title`, `Transcribe`) runs locally if device-capable.
3. Save → write to local Hive box; blobs (images, audio) saved to app documents directory; tags + reminders attached.

### Share-nearby flow
1. Select one or more notes → tap "Share nearby".
2. App requests Bluetooth + local-network permissions if not granted.
3. Discover advertising peers; user picks recipient by display name + avatar.
4. Handshake → encode payload (note JSON manifest + asset folder + sender's noti identity) → chunked transfer with progress.
5. Receiver lands payload in **received inbox**; preview the note rendered in the sender's noti theme; user accepts to merge into main library or discards.

### AI assist flow
1. Open a note → tap the AI assist affordance.
2. App checks device capability (RAM, OS version) via `device_info_plus`. If below threshold, the affordance hides.
3. Pick action → run on-device → stream result back into the note.
4. No request leaves the device.

## In scope

- Text, todo-list, image, audio, ink-drawing notes
- Tags, reminders (via `flutter_local_notifications`), search (via `string_similarity`)
- Custom per-note themes (NotiTheme: palette + pattern + accent)
- Per-user noti identity that ships with shared notes
- On-device STT, TTS, and small-LLM assist (capability-gated)
- P2P sharing over BLE / Wi-Fi-Direct / Multipeer (`flutter_nearby_connections`)
- Pretty animations, custom backgrounds (the existing pattern assets)
- Offline iconography, fonts, splash, launcher icon (already in the codebase)

## Out of scope (explicit — prevents creep)

- Any cloud sync, backup, or account system
- Web app or desktop app (mobile-only product)
- Real-time collaborative editing (shared notes are point-in-time copies, not live docs)
- Public profiles, discoverability beyond direct device proximity
- **Cloud LLM API calls — anywhere, ever**
- Markdown publishing or public share links
- Push notifications from a server (only local notifications via the OS)
- Telemetry, analytics, crash reporting that leaves the device
- Multi-language UI at MVP (English only; structure permits intl ARB later)

## Success criteria

1. With Wi-Fi and cellular off, end-to-end create/edit/search/delete works exactly as with full connectivity.
2. Two devices in the same room can complete a 3 MB note share in **under 10 seconds**.
3. On a 4 GB-RAM mid-tier device, on-device summarize returns in **under 5 seconds**.
4. On devices below the RAM threshold, AI affordances are hidden — never broken.
5. A received note renders the sender's NotiTheme (palette + pattern + accent) faithfully on the receiver's screen.
6. `flutter analyze` is clean and `flutter test` is green at every spec boundary.
7. No imports of `package:http`, `dart:io.HttpClient`, `package:dio`, or any cloud-SDK package appear in `lib/`.
