# 24 — share-nearby-flow

## Goal

Build the **sender-side share UI**: from a note (or a multiselect of notes), the user taps "Share nearby"; a sheet opens, discovers peers via `PeerService`, lets the user pick a recipient, sends the encoded payload via `ShareEncoder` → `PeerService.send`, shows chunked progress, and confirms success. The sheet uses the same App Style chrome pattern from Spec 11 — its background reflects the note's overlay so the act of sharing visually carries the note's identity. Cancel paths are explicit at every step.

This spec is **the user-facing front of the share feature**. Spec 25 handles the receive side.

## Dependencies

- [22-p2p-transport-service](22-p2p-transport-service.md) — discovery, invite, send, transfer events.
- [23-share-payload-codec](23-share-payload-codec.md) — `ShareEncoder` builds the payload bytes.
- [11-noti-theme-overlay](11-noti-theme-overlay.md) — sheet pattern + App Style chrome.
- [12-permissions-service](12-permissions-service.md) — Bluetooth/Nearby permissions if not yet granted.

## Agents & skills

**Pre-coding skills:**
- `flutter-build-responsive-layout` — three-phase sheet (discover / sending / done-failed) with smooth transitions.
- `flutter-add-widget-test` — sheet-phase widget tests via the fake peer service.

**After-coding agents:**
- `flutter-expert` — verify the sheet teardown cancels every subscription; queue progress is reported correctly.
- `ui-designer` — peer cards must read at a glance even with 5+ peers; chrome reflects sender's overlay (App Style).
- `accessibility-tester` — discovery list, peer cards, transfer progress all need labels and live-region announcements.

## Design Decisions

### Where the share affordance lives

- **Editor toolbar**: a "share nearby" button next to the paintbrush. Tapping shares the open note.
- **Home multiselect**: when one or more notes are selected, the action bar shows "Share nearby" — sends them as a sequence (one after another to the same peer).
- **Audio block long-press menu**: future enhancement — share a single audio block. Out of scope for this spec.

### Sheet structure

Three phases inside the same `DraggableScrollableSheet`:

1. **Discover** — header "Looking for nearby people…", scrollable list of `DiscoveredPeer` cards. Each card shows the peer's display name + a color chip painted with their `signaturePalette[2]` (their accent) so the sender recognizes who they're picking. The peer's signature accent (if any) renders as a small glyph overlaid on the chip — visual continuity with the home grid's swatch dot from Spec 11.
2. **Sending** — header "Sending to <peer name>", progress bar with byte count and percentage, cancel button. Background tinted to the note's overlay (App Style).
3. **Done / Failed** — green checkmark "Sent" with a short auto-dismiss timer, or red X "Couldn't send: <reason>" with retry button.

### Peer-card design (informed by research)

Each peer card is a horizontal pill:

```
┌──────────────────────────────────────────┐
│  ●  alex                          ·      │
│     ✦ Olive palette                      │
└──────────────────────────────────────────┘
```

- Left dot: peer's `signaturePalette[2]` (accent color).
- `✦`: peer's `signatureAccent` if known (in v1 we don't know peer signatures until handshake; for now this slot is empty until Spec 25 adds an "introduce yourself" handshake). For v1, just the accent chip + display name.
- The display name comes from the peer's `flutter_nearby_connections` advertised name, which we set to the local user's `NotiIdentity.displayName` when calling `PeerService.start(role: PeerRole.advertise, displayName: ...)`.

### Cancellation paths

- Pull down on the sheet → calls `PeerService.stop()` → sheet dismisses → if a transfer was in-flight, `PeerService.cancelTransfer(id)` runs first.
- Explicit cancel button during transfer → same.
- Dismiss after success → no cleanup needed; the peer connection is closed gracefully.

### Multi-note send

The sheet supports a queue. If the user shared three notes from home multiselect:

- Sheet picks the recipient.
- Sends note #1 → on success → sends note #2 → etc.
- Progress modal shows "Sending 2 of 3 — 47%".
- Any failure aborts the queue; partial successes are reported ("1 of 3 sent successfully; 2 failed").

### Security UX

The sheet's footer shows the privacy line: *"Sent over Bluetooth — never through the internet."* Same copy as the audio capture explainer; reinforces the offline promise at the moment the user is most likely to second-guess.

### State

`SendShareCubit` per route:

```dart
sealed class SendShareState { const SendShareState(); }
class Discovering extends SendShareState { final List<DiscoveredPeer> peers; ... }
class Sending extends SendShareState { final DiscoveredPeer peer; final TransferEvent progress; ... }
class Done extends SendShareState { final int notesSent; ... }
class Failed extends SendShareState { final String reason; ... }
```

Cubit subscribes to `peerStream` while in `Discovering`; subscribes to `transferStream` while in `Sending`. Cancellation closes subscriptions in `close()`.

## Implementation

### A. Files

```
lib/features/share/cubit/
├── send_share_cubit.dart
└── send_share_state.dart

lib/features/share/widgets/
├── share_nearby_sheet.dart
├── peer_card.dart
└── transfer_progress_panel.dart

lib/features/note_editor/widgets/
└── share_button.dart            ← editor toolbar entry

lib/features/home/widgets/
└── multiselect_action_bar.dart  ← extended to add "Share nearby" entry

test/features/share/cubit/
└── send_share_cubit_test.dart
```

### B. `SendShareCubit` — key flows

```dart
Future<void> open({required List<Note> notes}) async {
  emit(Discovering.empty);
  await _peer.start(role: PeerRole.both, displayName: _identity.displayName);
  _peerSub = _peer.peerStream.listen((peers) {
    emit(Discovering(peers: peers));
  });
}

Future<void> sendTo(DiscoveredPeer peer, List<Note> notes) async {
  for (var i = 0; i < notes.length; i++) {
    emit(Sending(peer: peer, queueIndex: i, queueSize: notes.length));
    try {
      final bytes = await _encoder.encode(note: notes[i], sender: _identity);
      final transferId = await _peer.send(peer.id, bytes);
      await for (final event in _peer.transferStream
          .where((e) => e.transferId == transferId)) {
        emit(Sending(peer: peer, queueIndex: i, queueSize: notes.length, progress: event));
        if (event.phase == TransferPhase.completed) break;
        if (event.phase == TransferPhase.cancelled || event.phase == TransferPhase.failed) {
          emit(Failed('Transfer ${event.phase.name}'));
          return;
        }
      }
    } on PayloadTooLarge {
      emit(Failed('Note too large to share'));
      return;
    }
  }
  emit(Done(notesSent: notes.length));
}

Future<void> cancel() async {
  await _peer.stop();
  await _peerSub?.cancel();
}
```

### C. `ShareNearbySheet`

Switches on cubit state to render the appropriate phase. When the sheet dismisses (drag-down or programmatic close), calls `cubit.cancel()`.

### D. Editor toolbar wiring

`share_button.dart` mounted next to `ai_assist_button.dart` and `overlay_picker_sheet`'s paintbrush trigger. Tapping calls:

```dart
ShareNearbySheet.show(context, notes: [bloc.state.note!]);
```

### E. Home multiselect bar

`multiselect_action_bar.dart` (extends the existing trash + tag bar) adds a "Share" icon. Tap → `ShareNearbySheet.show(context, notes: selectedNotes)`.

### F. App Style chrome

The sheet builds a `Theme(data: base.copyWith(extensions: overlay.applyTo(...)))` wrapper around its children using the **first** note's overlay (when sharing many, the first one's identity drives the chrome — feels intentional even if arbitrary).

## Success Criteria

- [ ] Files in Section A exist.
- [ ] **Manual smoke** (two devices on same Wi-Fi):
  - Device A creates a note with text + image + audio + custom overlay → opens it → tap share → sheet opens → sees Device B → tap B → sending pill → ~5 seconds → "Sent" → sheet auto-dismisses.
  - Device B receives a payload (Spec 25 handles UI; for this spec verify `peer_service`'s `payloadStream` fires with bytes that decode successfully via `ShareDecoder`).
  - Cancel mid-send: pull down sheet → transfer aborts on both ends → no partial file leaks on either side.
  - Multi-select 3 notes → share to peer → 3 transfers complete; failure on note 2 aborts the queue cleanly.
  - Note larger than 50 MB → encoder throws → "Note too large to share" error shown; nothing sent.
- [ ] Permission denial path: BLE / Nearby permissions denied → explainer sheet opens → settings deep-link works.
- [ ] Airplane mode + Bluetooth on: discovery works (BLE-only), send takes longer but completes.
- [ ] Sheet's chrome reflects the note's overlay (App Style verified visually).
- [ ] `flutter analyze` / format / test clean; offline gate clean.
- [ ] No invariant changed; invariants 3, 11 are exercised.

## References

- [22-p2p-transport-service](22-p2p-transport-service.md), [23-share-payload-codec](23-share-payload-codec.md), [11-noti-theme-overlay](11-noti-theme-overlay.md), [12-permissions-service](12-permissions-service.md)
- [`context/architecture.md`](../context/architecture.md) — invariants 3, 11, 12
- Skill: [`flutter-build-responsive-layout`](../.agents/skills/flutter-build-responsive-layout/SKILL.md)
- Agent: `flutter-expert` — verify the sheet teardown cancels every subscription
- Agent: `ui-designer` — peer cards must read at a glance even for 5+ peers
- Follow-up: [25-received-inbox](25-received-inbox.md) — sender-side complete only when receiver renders correctly.
