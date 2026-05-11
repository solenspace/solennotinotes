import 'package:noti_notes_app/services/share/peer_models.dart';

import 'fake_peer_service.dart';

/// Two [FakePeerService] instances wired so each one's [FakePeerService.sendBytes]
/// delivers to the other's [FakePeerService.payloadStream]. No network, no
/// Bluetooth, no `flutter_nearby_connections` plugin — the harness backs the
/// integration tests in `integration_test/share_e2e_test.dart` (Spec 28).
///
/// The pair identifies each side by [aPeerId] / [bPeerId]; that's the value
/// the receiver sees on the inbound [IncomingPayload.peerId]. The hook fires
/// after `sendBytes` validates payload size and records its action, so cancel
/// scenarios (the sender simply never calls `sendBytes`) and oversize
/// scenarios (the encoder throws before the transport is invoked) both fall
/// out naturally.
class InMemoryPeerPair {
  InMemoryPeerPair({
    this.aPeerId = 'peer-a',
    this.bPeerId = 'peer-b',
  }) {
    a.onSendBytes = (_, bytes, __) {
      b.enqueueIncomingPayload(IncomingPayload(peerId: aPeerId, bytes: bytes));
    };
    b.onSendBytes = (_, bytes, __) {
      a.enqueueIncomingPayload(IncomingPayload(peerId: bPeerId, bytes: bytes));
    };
  }

  final FakePeerService a = FakePeerService();
  final FakePeerService b = FakePeerService();
  final String aPeerId;
  final String bPeerId;

  Future<void> dispose() async {
    await a.dispose();
    await b.dispose();
  }
}
