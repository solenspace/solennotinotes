# 25 — received-inbox

## Goal

Build the **receiver-side share UI**: when a peer sends a note via Spec 24, our `PeerService.payloadStream` fires with bytes; we decode via `ShareDecoder` (Spec 23); a verified `IncomingShare` lands in a new `received_inbox` Hive box. The user sees a small badge on the home AppBar (count of pending), opens the inbox screen, previews each incoming note rendered with the **sender's overlay faithfully** (per [project-overview.md](../context/project-overview.md) success criterion 5), and chooses **Accept** (merge into the user's library) or **Discard** (delete bytes from disk). The "from @sender" chip from Spec 11 finally has live data — display name + accent glyph from the verified manifest.

This closes the share loop end-to-end. After this spec, two devices can exchange a note and the receiver renders it as the sender intended, with full unreadability escape hatch.

## Dependencies

- [22-p2p-transport-service](22-p2p-transport-service.md) — `payloadStream` is the entry point.
- [23-share-payload-codec](23-share-payload-codec.md) — `ShareDecoder.decode()` produces `IncomingShare`.
- [11-noti-theme-overlay](11-noti-theme-overlay.md) — `from @sender` chip + "Convert to mine" path.
- [04-repository-layer](04-repository-layer.md) — repo pattern for the inbox.

## Agents & skills

**Pre-coding skills:**
- `flutter-apply-architecture-best-practices` — repository + cubit + listener-service pattern.
- `flutter-add-widget-test` — inbox row + preview widget tests.

**After-coding agents:**
- `flutter-expert` — invoke after the inbox screen lands; rendering the sender's overlay during preview is the spec's hardest visual proof.
- `ui-designer` — verify the from-sender chip, accept/discard affordances, and the Tot-style swatch dot read coherently.
- `accessibility-tester` — preview screen must have proper screen-reader labels for the chip and tagline.

## Design Decisions

### Two new repositories

- **`ReceivedInboxRepository`** — Hive box `received_inbox_v1`, stores entries keyed by `share_id`. Each record holds the manifest's metadata + the path prefix where assets were extracted.
- **No new HTTP, no new transports** — receive happens only when the user opens the share sheet (sender side via Spec 24). Receivers don't passively listen unless they're inside the share UI.

### Listening surface

The `PeerService.payloadStream` is *not* subscribed at app launch. Per invariant 3 (opt-in), subscription happens only when the user opens the share sheet (either as sender via Spec 24, or as receiver via a new "Open share" action in Settings → "Receive a shared note"). When subscribed and a payload arrives:

1. Decode via `ShareDecoder`.
2. If `DecodeOk`: write to `received_inbox` Hive box; assets already extracted to `<app_documents>/inbox/<share_id>/...`.
3. Emit a state change → inbox badge increments.
4. If decode fails: surface error toast; no inbox entry created; bytes discarded.

### Inbox screen

New route at `/inbox` (or via a Settings → Inbox row). Lists pending received shares in arrival order:

- Each row shows the sender's display name, accent chip, signature glyph (if any), tagline, the note's title (or first 40 chars of body), and a relative timestamp.
- Tapping a row opens a **preview** screen that renders the note exactly as it would appear in the editor — with the sender's `NotiThemeOverlay` applied via the App Style chrome, including pattern, palette, and the from-sender chip.
- Two buttons at the bottom: **Accept** and **Discard**.

### Accept

`ReceivedInboxRepository.accept(shareId)`:

1. Reconstructs the `Note` from the stored manifest.
2. The note's overlay-shaped legacy fields (`colorBackground`, `fontColor`, `patternImage`, `gradient`) are populated from the manifest's `overlay` object so the legacy schema (pre-Spec-04b) renders correctly.
3. The `fromIdentityId` field on `Note.toOverlay()` is set to the sender's `NotiIdentity.id` — the from-sender chip remains visible until the user taps "Convert to mine".
4. Asset files are **moved** (not copied) from `<app_documents>/inbox/<share_id>/...` to `<app_documents>/notes/<note_id>/{audio,images}/...`.
5. The note is saved to `NotesRepository`.
6. The inbox entry is removed.
7. UI navigates to the new note in the editor.

### Discard

`ReceivedInboxRepository.discard(shareId)`:

1. Deletes the asset directory `<app_documents>/inbox/<share_id>/`.
2. Removes the inbox entry from Hive.
3. UI returns to the inbox list.

### Preserving sender attribution

Once accepted, the note's `fromIdentityId` stays set — even after the receiver edits or shares the note onward. This is intentional: provenance travels. If the receiver shares onward, the second receiver sees the original sender's identity (per the manifest), not the relayer's. Future spec can add a "relayed by" chain.

The receiver can clear the from-sender chip via the existing **"Convert to mine"** menu in the chip from Spec 11. That replaces the overlay with the receiver's own NotiIdentity defaults and clears `fromIdentityId`.

### Inbox badge

`InboxBadgeCubit` subscribes to `ReceivedInboxRepository.watchAll()`. Renders count on the home AppBar (top-right, near the search icon). Tapping the badge navigates to the inbox screen.

## Implementation

### A. Files

```
lib/repositories/received_inbox/
├── received_inbox_repository.dart
└── hive_received_inbox_repository.dart

lib/features/inbox/
├── cubit/
│   ├── inbox_cubit.dart
│   ├── inbox_state.dart
│   ├── inbox_badge_cubit.dart
│   └── inbox_listener_service.dart   ← subscribes payloadStream when receive is enabled
├── screen.dart
└── widgets/
    ├── inbox_row.dart
    └── share_preview_panel.dart

lib/models/
└── received_share.dart            ← in-memory representation of an inbox entry

test/features/inbox/cubit/
└── inbox_cubit_test.dart
```

### B. `ReceivedShare` model

Holds `shareId`, sender metadata, `Note` reconstructed from manifest, asset path prefix, received_at timestamp.

### C. `ReceivedInboxRepository`

```dart
abstract class ReceivedInboxRepository {
  Future<void> init();
  Stream<List<ReceivedShare>> watchAll();
  Future<List<ReceivedShare>> getAll();
  Future<void> insert(ReceivedShare share);
  Future<Note> accept(String shareId);
  Future<void> discard(String shareId);
}
```

### D. `InboxListenerService`

```dart
class InboxListenerService {
  InboxListenerService({
    required this.peer,
    required this.decoder,
    required this.inbox,
    required this.keypair,
  });

  StreamSubscription<IncomingPayload>? _sub;

  Future<void> startReceiving() async {
    await peer.start(role: PeerRole.both, displayName: ...);
    _sub = peer.payloadStream.listen((p) async {
      final result = await decoder.decode(p.bytes);
      if (result is DecodeOk) {
        await inbox.insert(result.share);
      } else {
        // log + emit error toast (debug only)
      }
    });
  }

  Future<void> stopReceiving() async {
    await _sub?.cancel();
    await peer.stop();
  }
}
```

The receive surface is opened via Settings → "Receive a shared note" (which calls `startReceiving()` and shows a "discoverable" affordance) or implicitly when the share sheet from Spec 24 is open (sender path also receives, in case the other side wants to share back).

### E. UI

`InboxScreen` shows a list of `ReceivedShare`s. Each `InboxRow` renders sender chip + tagline + title preview. Tap → push `SharePreviewPanel` with the note rendered via `Theme(data: base.copyWith(extensions: overlay.applyTo(...)))`. Bottom sheet with Accept / Discard buttons.

`InboxBadgeCubit` exposes `int count`; home AppBar consumes it.

### F. Update home screen + main.dart

- Add inbox badge to home AppBar.
- Register `ReceivedInboxRepository`, `InboxListenerService` in the provider tree.
- Wire the `from @sender` chip's data source to read from `Note.toOverlay().fromIdentityId` — already done in Spec 11; the chip becomes alive when received notes carry the field.

### G. Tests

- `inbox_cubit_test.dart`: scripted decoder fake feeds `IncomingShare`s; cubit accumulates them; accept moves files + creates note; discard deletes files.
- `received_inbox_repository_test.dart`: temp Hive box round-trip with 1 entry → multiple → accept → file system reflects move.

## Success Criteria

- [ ] Files in Section A exist.
- [ ] **Manual smoke** (two iOS devices):
  - Device A creates a note "Dinner ideas" with `Olive` palette + `polygons` pattern → shares → Device B's inbox badge ticks to 1.
  - On B: open inbox → see row "alex • Dinner ideas" with alex's accent chip → tap → preview shows the note in alex's olive palette + polygons pattern + from-alex chip in the AppBar.
  - Tap Accept → editor opens with the note saved locally; tap from-alex chip → "Convert to mine" → palette/pattern revert to receiver's identity defaults.
  - Tap Discard on a different incoming share → inbox row removed; `<app_documents>/inbox/<share_id>/` directory gone.
- [ ] Tampered payload received: bytes decode to `DecodeSignatureInvalid` → no inbox entry created; debug toast shown.
- [ ] Multiple shares in flight: badge counts correctly; each preview opens independently.
- [ ] Accepting a share does not lose any of the sender's overlay fields (palette, pattern, accent, tagline render in preview AND after accept).
- [ ] Inbox screen renders correctly with 0 entries (empty state) and 50 entries (scrollable).
- [ ] `flutter analyze` / format / test clean; offline gate clean.
- [ ] All 12 invariants in `context/architecture.md` reverified by code; especially invariant 4 (received → inbox → accept) and 12 (sender's NotiIdentity travels and renders faithfully).

## References

- [22](22-p2p-transport-service.md), [23](23-share-payload-codec.md), [24](24-share-nearby-flow.md), [11](11-noti-theme-overlay.md)
- [`context/architecture.md`](../context/architecture.md), [`context/project-overview.md`](../context/project-overview.md)
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md)
- Skill: [`flutter-add-widget-test`](../.agents/skills/flutter-add-widget-test/SKILL.md)
- Agent: `flutter-expert` — invoke after the inbox screen lands; rendering the sender's overlay during preview is the spec's hardest visual proof
- Agent: `accessibility-tester` — preview screen must have proper screen-reader labels for the from-sender chip
- This spec **closes Phase 6**. Phase 7 (polish) follows.
