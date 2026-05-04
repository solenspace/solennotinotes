# 22 — p2p-transport-service

## Goal

Wrap `flutter_nearby_connections` in a typed `PeerService` so consumers can discover nearby devices, advertise this device, accept/reject incoming connection requests, and exchange byte payloads — without ever importing the plugin directly. This is **Phase 6's foundation**: Spec 23 (codec) builds the payload, Spec 24 (share flow) drives the UI on top of this transport, Spec 25 (received inbox) handles incoming. The transport lives at `lib/services/share/peer_service.dart` and is the only place `flutter_nearby_connections` is imported. Per [architecture.md](../context/architecture.md) invariants 3 (opt-in advertising) and 11 (chunked, capped, cancellable transfers), the service ships with a strict opt-in lifecycle: nothing scans or advertises until the user enters the share flow.

This spec also adds the **Ed25519 keypair to `NotiIdentity`** that was deferred from Spec 9 — every shared note gets signed by the sender, so receivers can verify the sender's identity matches what the overlay claims.

## Dependencies

- [9-noti-identity](09-noti-identity.md) — `NotiIdentity` schema; this spec adds two fields (`publicKey`, `privateKeyEncryptedRef`).
- [12-permissions-service](12-permissions-service.md) — BLE / Nearby Wi-Fi / Bluetooth permissions plumbing.
- [17-device-capability-service](17-device-capability-service.md) — share is gated by Bluetooth-permission availability and OS version.

## Agents & skills

**Pre-coding skills:**
- `flutter-apply-architecture-best-practices` — service-wrapper + stream cancellation pattern.
- `dart-flutter-patterns` — keypair handling + secure storage conventions.

**After-coding agents:**
- `flutter-expert` — invoke after wiring; multi-platform peer APIs leak streams easily.
- `code-reviewer` — confirm the Plugin viability check ran (per Section 0); confirm keypair handling never logs the private key, never persists it to Hive.

## Design Decisions

### Package: `flutter_nearby_connections` (^1.1.x) — **viability probe required**

- Apple Multipeer Connectivity on iOS; Google Nearby Connections + Wi-Fi-Direct on Android.
- Single API for discovery + advertising + connection + payload transfer.
- Supports messages, byte streams, and files (the codec spec uses files for assets).
- BSD-2 licensed; no transitive network imports — verified clean against the offline gate.

**Risk**: validation found the package dormant (last update ~2 years ago). iOS 19+ behavior is unverified. The first implementation step is a viability probe (Section 0 below); the spec extends to write platform channels if the probe fails.

### Plugin viability check (Section 0 of Implementation)

Before any code dependent on the plugin lands, run a 30-line probe on iOS 17+ + Android 14+:

1. Add the dep, call `start(advertiseAndDiscover, ...)` from a throwaway widget.
2. Run two sims (or two physical devices), confirm peers appear in `peerStream` within 10 seconds.
3. `invite()` from one side, `acceptInvite()` from the other; confirm connection state.
4. `send(...)` 1 KB of bytes; confirm `payloadStream` fires on the receiver.

**If the probe is green** → keep the plugin; proceed with §A onwards as written.

**If the probe is red** (build error / timeout / API drift) → drop the dep and write platform channels: `MultipeerConnectivity` (iOS, Swift) + `Nearby Connections API` (Android, Kotlin). Spec 22 then ~doubles in size; defer §A onwards until both native sides are wired. Document the swap in `context/progress-tracker.md` as architecture decision update for invariant 4.

### Lifecycle: explicit start, explicit stop

`PeerService` exposes `start(role)` and `stop()`. Roles: `Role.discover` (scan only), `Role.advertise` (visible to scanners), `Role.both` (scan + advertise). The default in the share flow is `Role.both` so two users can find each other regardless of who initiated. **The service starts no listener at app launch.** The share UI (Spec 24) calls `start(...)` when the user taps Share, and `stop()` when the sheet dismisses or a transfer completes.

### Connection model

- `peerStream`: `Stream<List<DiscoveredPeer>>` — what's currently visible.
- `inviteStream`: `Stream<IncomingInvite>` — when a peer asks to connect to us.
- `payloadStream`: `Stream<IncomingPayload>` — when bytes/files arrive.
- `invite(peerId)`, `acceptInvite(inviteId)`, `rejectInvite(inviteId)`.
- `send(peerId, bytes)` and `sendFile(peerId, filePath)`.
- `disconnect(peerId)`.

### Identity signing

Every `NotiIdentity` carries an Ed25519 keypair from this spec onward. The private key lives in `flutter_secure_storage` (Keychain on iOS, EncryptedSharedPreferences on Android); the public key lives in Hive. The codec spec (23) signs every share payload with the private key; receivers verify with the public key.

`flutter_secure_storage` adds one runtime dep but **does not break offline invariant 1** — it's a wrapper over local OS-managed keystores; no network imports. Verified at offline gate.

### Identity migration

`HiveNotiIdentityRepository.init()` extends to: if the loaded identity has no public key, generate a fresh keypair, save the public key in the Hive record, and the private key in secure storage under `noti_identity_private_<id>`. This runs once per install.

### Size cap, chunking

The transport hardcodes a **50 MB ceiling** per payload (matches invariant 11). The codec ensures payloads stay under this. The plugin's file transfer mode chunks transparently; we expose `Stream<TransferProgress>` to the UI so the user sees a percentage.

### Cancellation

Either side can cancel a transfer. `PeerService.cancelTransfer(transferId)` aborts the chunked send/receive and emits `TransferEvent.cancelled`. The plugin handles cleanup on both ends.

### What's NOT in this spec

- **Per-payload encryption**. The transport is BLE / Multipeer, both already encrypted at the transport layer. We don't double-encrypt. (Future spec can add app-layer encryption if threat model changes.)
- **Cross-platform discovery between iOS and Android**. `flutter_nearby_connections` documents inconsistent cross-OS behavior. We test iOS↔iOS and Android↔Android first; cross-OS works when it works, fallback message clarifies if it doesn't.
- **Background advertising** — never. Always foreground-only.

## Implementation

### A. Files to create

```
lib/services/share/
├── peer_service.dart                  ← abstract + concrete (FlutterNearbyPeerService)
└── peer_models.dart                   ← DiscoveredPeer, IncomingInvite, IncomingPayload, etc.

lib/repositories/noti_identity/
└── (extends existing files; adds keypair fields)

lib/services/crypto/
├── keypair_service.dart               ← abstract Ed25519 generate / sign / verify
└── flutter_secure_keypair_service.dart ← concrete using flutter_secure_storage + cryptography

test/services/share/
└── fake_peer_service.dart
```

### B. `pubspec.yaml`

```yaml
dependencies:
  flutter_nearby_connections: ^1.1.2
  flutter_secure_storage: ^9.2.2
  cryptography: ^2.7.0
```

`cryptography` is a pure-Dart library that supports Ed25519 without any platform binary — so it doesn't introduce a network surface; verified at offline gate.

### C. `peer_models.dart`

```dart
import 'package:equatable/equatable.dart';

class DiscoveredPeer extends Equatable {
  const DiscoveredPeer({required this.id, required this.displayName});
  final String id;
  final String displayName;
  @override
  List<Object?> get props => [id, displayName];
}

class IncomingInvite extends Equatable {
  const IncomingInvite({required this.id, required this.peerId, required this.peerName});
  final String id;
  final String peerId;
  final String peerName;
  @override
  List<Object?> get props => [id, peerId, peerName];
}

class IncomingPayload extends Equatable {
  const IncomingPayload({required this.peerId, required this.bytes});
  final String peerId;
  final List<int> bytes;
  @override
  List<Object?> get props => [peerId, bytes];
}

enum TransferPhase { queued, sending, receiving, completed, cancelled, failed }

class TransferEvent extends Equatable {
  const TransferEvent({
    required this.transferId,
    required this.phase,
    required this.bytes,
    required this.total,
  });
  final String transferId;
  final TransferPhase phase;
  final int bytes;
  final int total;
  double get fraction => total == 0 ? 0 : bytes / total;
  @override
  List<Object?> get props => [transferId, phase, bytes, total];
}
```

### D. `peer_service.dart` (abstract)

```dart
import 'peer_models.dart';

enum PeerRole { discover, advertise, both }

abstract class PeerService {
  Future<void> start({required PeerRole role, required String displayName});
  Future<void> stop();

  Stream<List<DiscoveredPeer>> get peerStream;
  Stream<IncomingInvite> get inviteStream;
  Stream<IncomingPayload> get payloadStream;
  Stream<TransferEvent> get transferStream;

  Future<void> invite(String peerId);
  Future<void> acceptInvite(String inviteId);
  Future<void> rejectInvite(String inviteId);
  Future<String> send(String peerId, List<int> bytes); // returns transferId
  Future<String> sendFile(String peerId, String filePath);
  Future<void> cancelTransfer(String transferId);
  Future<void> disconnect(String peerId);

  bool get isActive;
}
```

### E. `KeypairService`

```dart
abstract class KeypairService {
  /// Returns the user's public key. Generates one (and stores both halves)
  /// on first call.
  Future<List<int>> publicKey();

  /// Signs [bytes] with the user's private key.
  Future<List<int>> sign(List<int> bytes);

  /// Verifies a signature for arbitrary data + public key.
  Future<bool> verify({
    required List<int> bytes,
    required List<int> signature,
    required List<int> publicKey,
  });
}
```

Concrete impl uses `cryptography`'s `Ed25519` algorithm with `flutter_secure_storage` for the private key.

### F. `NotiIdentity` schema additions

```dart
// New fields on NotiIdentity:
final List<int> publicKey;        // 32-byte Ed25519 public key
// Private key NOT stored on the model — held by KeypairService in secure storage
```

`NotiIdentity.toJson()` adds `publicKey` (base64). `fromJson()` reads it back; if absent (legacy record), the field is set to empty and the migration in `HiveNotiIdentityRepository.init()` regenerates it.

### G. Permission flow

When `start(role: ...)` is called, the service:

1. Calls `permissions.requestBluetoothScan()`, `requestBluetoothConnect()`, `requestBluetoothAdvertise()` (or matching iOS-only Bluetooth permission via the explainer sheet). Any denial → throws `PeerStartFailed.permissionDenied`.
2. On Android 13+, also `requestNearbyWifiDevices()` for Wi-Fi-Direct fallback.
3. On success, calls the underlying plugin's `init` + `discoverServices` / `startAdvertisingPeer`.

### H. `lib/main.dart`

```dart
RepositoryProvider<KeypairService>.value(value: FlutterSecureKeypairService()),
RepositoryProvider<PeerService>.value(value: FlutterNearbyPeerService(
  permissions: ctx.read<PermissionsService>(),
)),
```

### I. Update `context/architecture.md`

- Stack table: add `flutter_nearby_connections`, `flutter_secure_storage`, `cryptography`.
- Storage model: `NotiIdentity` gains `publicKey`; private key stored in secure storage.
- Reaffirm invariants 3 (opt-in), 11 (chunked + capped), 12 (NotiIdentity travels).

### J. Update `context/code-standards.md`

Forbidden imports (hygiene): `package:flutter_nearby_connections`, `package:flutter_secure_storage` confined to `lib/services/share/` and `lib/services/crypto/`.

### K. Tests

- `fake_peer_service.dart` — controllable streams + scripted invite/payload events.
- `keypair_service_test.dart` — generate + sign + verify round trip.
- `peer_service_integration_test.dart` (manual harness) — runs on two physical devices to verify discover + send.

## Success Criteria

- [ ] Files in Section A exist; `flutter_nearby_connections` import confined to `peer_service.dart`.
- [ ] `bash scripts/check-offline.sh` exits 0 with the new entries.
- [ ] **Manual smoke** (two iOS devices on same network):
  - Both open the share sheet (preview from Spec 24) → both see each other in `peerStream` within 5 seconds.
  - Device A invites Device B → B sees the invite in `inviteStream`, accepts → connection established.
  - Device A sends a 1 MB byte payload → B sees `IncomingPayload` with the same bytes.
  - Cancel mid-transfer → both sides emit `TransferEvent.cancelled`.
  - Close the share sheet → `stop()` runs → both peer streams empty.
- [ ] On Android 13+: same flow works with the Nearby + Wi-Fi-Direct combo.
- [ ] Airplane mode (Wi-Fi off + cellular off) but Bluetooth on: BLE discovery works (slower but functional).
- [ ] `KeypairService` round-trip: sign 1KB, verify with the public key, succeed; verify with a different public key, fail.
- [ ] On a fresh install, `NotiIdentity.publicKey` is non-empty after `init()`. The corresponding private key exists in secure storage and persists across app restarts.
- [ ] `flutter analyze` / format / test clean; offline gate clean.
- [ ] No invariant in `context/architecture.md` is changed; invariants 3, 11, 12 newly enforced by code.

## References

- [`context/architecture.md`](../context/architecture.md), [`context/project-overview.md`](../context/project-overview.md)
- [9-noti-identity](09-noti-identity.md), [12-permissions-service](12-permissions-service.md)
- Plugin: <https://pub.dev/packages/flutter_nearby_connections>
- Plugin: <https://pub.dev/packages/flutter_secure_storage>
- Plugin: <https://pub.dev/packages/cryptography>
- Skill: [`flutter-apply-architecture-best-practices`](../.agents/skills/flutter-apply-architecture-best-practices/SKILL.md)
- Agent: `flutter-expert` — invoke after wiring; multi-platform peer APIs leak streams easily
- Agent: `code-reviewer` — confirm keypair handling never logs private key, never writes it to Hive
- Follow-up: [23-share-payload-codec](23-share-payload-codec.md) builds the wire format on top.
