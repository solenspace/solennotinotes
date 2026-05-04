# 28 — integration-tests-share

## Goal

Add an **integration test harness** for the share end-to-end: two simulated peers exchange a note over an in-process `PeerService` substitute, and the test asserts that the receiver's accept path produces a `Note` byte-equal (modulo file paths) to the sender's source. This catches regressions in the codec, the encoder/decoder pair, the inbox repository, and the overlay-faithful render — without requiring two physical devices for every PR.

The harness sets a precedent for future integration specs (AI happy-path E2E, audio capture E2E).

## Dependencies

- [22-p2p-transport-service](22-p2p-transport-service.md), [23-share-payload-codec](23-share-payload-codec.md), [24-share-nearby-flow](24-share-nearby-flow.md), [25-received-inbox](25-received-inbox.md).

## Agents & skills

**Pre-coding skills:**
- `flutter-add-integration-test` — `integration_test` package, `flutter drive` workflow.
- `dart-generate-test-mocks` — fake / stub conventions for the in-process peer harness.
- `dart-collect-coverage` — coverage report for the share path.

**After-coding agents:**
- `test-automator` — verify failure modes (cancel, tampered, oversize) are exercised, not just the happy path.
- `code-reviewer` — confirm fixtures stay <1.5 MB and no real network/Bluetooth gets touched.

## Design Decisions

- **Test driver**: Flutter's built-in `integration_test` package.
- **In-process two-peer harness**: an `InMemoryPeerService` wires two `FakePeerService` instances in opposite directions — sender's `peerStream` lists the receiver and vice versa; `send(...)` directly enqueues bytes into the other side's `payloadStream`. No network, no Bluetooth, no real `flutter_nearby_connections` plugin involvement. Fast (sub-second end-to-end).
- **Real `ShareEncoder` + `ShareDecoder`**: production codec runs on real bytes. The harness only fakes the transport.
- **Real `NotesRepository` + `ReceivedInboxRepository`**: tests use temp Hive boxes per `setUp`; this proves the storage path works end-to-end.
- **Asset coverage**: harness creates a 1 MB image + 200 KB audio fixture in temp; full codec round-trips through the archive layer.

## Implementation

### A. Files

```
integration_test/
├── share_e2e_test.dart
└── fixtures/
    ├── mini_image.jpg            ← 1 MB fixture
    └── mini_audio.m4a            ← 200 KB fixture

test/services/share/
└── in_memory_peer_service.dart    ← two-instance pair
```

### B. `pubspec.yaml`

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```

### C. Two-peer harness

```dart
class InMemoryPeerPair {
  final FakePeerService a = FakePeerService();
  final FakePeerService b = FakePeerService();

  InMemoryPeerPair() {
    a.linkTo(b);
    b.linkTo(a);
  }
}

extension on FakePeerService {
  void linkTo(FakePeerService other) {
    onSend = (peerId, bytes) async {
      other.receivePayloadInternal(peerId, bytes);
      return _nextTransferId();
    };
  }
}
```

### D. Test scenarios

```dart
testWidgets('share-e2e: sender and receiver exchange a styled note', (tester) async {
  // 1. Pair of peer services.
  final pair = InMemoryPeerPair();

  // 2. Sender stack.
  final senderRepo = HiveNotesRepository();
  await senderRepo.init();
  final senderIdentity = NotiIdentity.fresh(displayName: 'alex');
  final encoder = ShareEncoder(keypair: FakeKeypairService.alex(), notes: senderRepo);

  // 3. Receiver stack.
  final receiverInbox = HiveReceivedInboxRepository();
  await receiverInbox.init();
  final decoder = ShareDecoder(keypair: FakeKeypairService.bob());

  // 4. Sender creates a note with overlay + image + audio.
  final note = _buildNote(
    overlay: kCuratedPalettes[2],   // Moss
    imagePath: 'integration_test/fixtures/mini_image.jpg',
    audioPath: 'integration_test/fixtures/mini_audio.m4a',
  );
  await senderRepo.save(note);

  // 5. Encode + send.
  final bytes = await encoder.encode(note: note, sender: senderIdentity);
  await pair.a.send('peer-bob', bytes);

  // 6. Receiver decodes the inbound payload.
  final inbound = await pair.b.payloadStream.first;
  final result = await decoder.decode(inbound.bytes);
  expect(result, isA<DecodeOk>());
  await receiverInbox.insert((result as DecodeOk).share);

  // 7. Assert the inbox has 1 entry.
  final inboxAll = await receiverInbox.getAll();
  expect(inboxAll, hasLength(1));
  expect(inboxAll.first.note.title, note.title);

  // 8. Accept the share; verify the rebuilt note matches.
  final receiverNotesRepo = HiveNotesRepository();
  await receiverNotesRepo.init();
  final accepted = await receiverInbox.accept(inboxAll.first.shareId);
  expect(accepted.title, note.title);
  expect(accepted.colorBackground, note.colorBackground);
  expect(accepted.patternImage, note.patternImage);
  expect(accepted.blocks.length, note.blocks.length);
});
```

Additional scenarios to cover:

- Cancel mid-transfer (sender-side cancel) → receiver gets nothing → inbox empty.
- Tampered bytes → receiver's `DecodeSignatureInvalid` → inbox empty + error logged.
- Payload > 50 MB → encoder throws `PayloadTooLarge` → never reaches receiver.

### E. Run command

```bash
flutter test integration_test/share_e2e_test.dart
```

CI runs this on macOS (later spec); locally the developer runs as needed.

## Success Criteria

- [ ] `integration_test/share_e2e_test.dart` covers the four scenarios in Section D.
- [ ] All scenarios pass on a fresh checkout.
- [ ] No real Bluetooth / network used; harness is in-process.
- [ ] Fixtures < 1.5 MB total in repo size.
- [ ] `flutter analyze` / format clean.
- [ ] No invariant changed.

## References

- [22](22-p2p-transport-service.md), [23](23-share-payload-codec.md), [24](24-share-nearby-flow.md), [25](25-received-inbox.md)
- Skill: [`flutter-add-integration-test`](../.agents/skills/flutter-add-integration-test/SKILL.md)
- Agent: `test-automator` — invoke after harness lands; verify failure modes are exercised
- Follow-up: cross-device integration via `flutter drive` against real BLE — future polish spec.
