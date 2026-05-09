import 'package:flutter_test/flutter_test.dart';
import 'package:noti_notes_app/services/share/peer_models.dart';

void main() {
  group('TransferEvent.fraction', () {
    TransferEvent build(int bytes, int total) => TransferEvent(
          transferId: 'tx',
          peerId: 'peer',
          direction: TransferDirection.send,
          phase: TransferPhase.inProgress,
          bytes: bytes,
          total: total,
        );

    test('returns 0 when total is zero', () {
      expect(build(0, 0).fraction, 0.0);
      expect(build(10, 0).fraction, 0.0);
    });

    test('clamps to [0, 1]', () {
      expect(build(50, 100).fraction, 0.5);
      expect(build(150, 100).fraction, 1.0);
      expect(build(-10, 100).fraction, 0.0);
    });
  });

  test('TransferEvent.isTerminal covers completed/cancelled/failed', () {
    for (final phase in [
      TransferPhase.completed,
      TransferPhase.cancelled,
      TransferPhase.failed,
    ]) {
      final ev = TransferEvent(
        transferId: 't',
        peerId: 'p',
        direction: TransferDirection.receive,
        phase: phase,
        bytes: 1,
        total: 1,
      );
      expect(ev.isTerminal, isTrue, reason: '$phase should be terminal');
    }
    expect(
      const TransferEvent(
        transferId: 't',
        peerId: 'p',
        direction: TransferDirection.send,
        phase: TransferPhase.inProgress,
        bytes: 0,
        total: 1,
      ).isTerminal,
      isFalse,
    );
  });

  test('PeerStartFailed factories produce distinct, equatable instances', () {
    expect(
      const PeerStartFailed.permissionDenied('bluetoothScan').toString(),
      contains('bluetoothScan'),
    );
    expect(
      const PeerStartFailed.alreadyActive(),
      isA<PeerStartFailed>(),
    );
  });
}
