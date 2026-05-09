import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noti_notes_app/features/share/cubit/share_nearby_cubit.dart';
import 'package:noti_notes_app/features/share/cubit/share_nearby_state.dart';
import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/services/share/peer_models.dart';
import 'package:noti_notes_app/services/share/share_codec.dart';
import 'package:noti_notes_app/services/share/share_models.dart';

import '../../../services/crypto/fake_keypair_service.dart';
import '../../../services/share/fake_peer_service.dart';

Note _note(String id) => Note(
      <String>{},
      null,
      null,
      <Map<String, dynamic>>[],
      null,
      null,
      id: id,
      title: 'note $id',
      content: '',
      dateCreated: DateTime.utc(2026),
      colorBackground: const Color(0xFFEAE7DD),
      fontColor: const Color(0xFF222222),
      hasGradient: false,
    );

NotiIdentity _identity({String name = 'mateo'}) => NotiIdentity.fresh(displayName: name);

DiscoveredPeer _peer(String id, {String name = 'alex'}) => DiscoveredPeer(
      id: id,
      displayName: name,
      state: PeerConnectionState.found,
    );

TransferEvent _evt({
  required String transferId,
  required String peerId,
  required TransferPhase phase,
  int bytes = 0,
  int total = 100,
  String? errorMessage,
}) =>
    TransferEvent(
      transferId: transferId,
      peerId: peerId,
      direction: TransferDirection.send,
      phase: phase,
      bytes: bytes,
      total: total,
      errorMessage: errorMessage,
    );

class _ScriptedEncoder extends ShareEncoder {
  _ScriptedEncoder() : super(keypair: FakeKeypairService());

  Object? throwOn;
  int callCount = 0;
  final List<String> encodedNoteIds = <String>[];

  @override
  Future<OutgoingShare> encode({required Note note, required NotiIdentity sender}) async {
    callCount++;
    encodedNoteIds.add(note.id);
    final t = throwOn;
    if (t != null) throw t;
    return OutgoingShare(bytes: const <int>[1, 2, 3], shareId: 'sid-${note.id}');
  }
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  late FakePeerService peer;
  late _ScriptedEncoder encoder;
  late NotiIdentity identity;
  late ShareNearbyCubit cubit;

  setUp(() {
    peer = FakePeerService();
    encoder = _ScriptedEncoder();
    identity = _identity();
    cubit = ShareNearbyCubit(
      peerService: peer,
      encoder: encoder,
      identity: () => identity,
    );
  });

  tearDown(() async {
    await cubit.close();
    await peer.dispose();
  });

  group('ShareNearbyCubit.open', () {
    test('starts the transport with the local display name and forwards peers', () async {
      await cubit.open([_note('a')]);
      peer.peers.add([_peer('p1'), _peer('p2', name: 'sam')]);
      await _settle();

      expect(peer.actionLog.first, 'start:both:${identity.displayName}');
      expect(cubit.state.phase, ShareNearbyPhase.discovering);
      expect(cubit.state.peers, hasLength(2));
      expect(cubit.state.queue, hasLength(1));
    });

    test('failed start surfaces permissionStartFailed', () async {
      peer.failOnStart = const PeerStartFailed.permissionDenied('scan');
      await cubit.open([_note('a')]);

      expect(cubit.state.phase, ShareNearbyPhase.failed);
      expect(cubit.state.failure, ShareNearbyFailure.permissionStartFailed);
      expect(cubit.state.failureDetail, contains('scan'));
    });
  });

  group('ShareNearbyCubit.sendTo', () {
    test('happy path: encode → sendBytes → completed', () async {
      await cubit.open([_note('a')]);
      peer.peers.add([_peer('p1')]);
      await _settle();

      final sendFuture = cubit.sendTo(_peer('p1'));
      await _settle();

      peer.transfers.add(
        _evt(transferId: 'tx-1', peerId: 'p1', phase: TransferPhase.inProgress, bytes: 50),
      );
      peer.transfers.add(
        _evt(transferId: 'tx-1', peerId: 'p1', phase: TransferPhase.completed, bytes: 100),
      );
      await sendFuture;

      expect(encoder.callCount, 1);
      expect(
        peer.actionLog.where((l) => l.startsWith('sendBytes:')).single,
        startsWith('sendBytes:p1:3:tx-1'),
      );
      expect(cubit.state.phase, ShareNearbyPhase.completed);
      expect(cubit.state.queueIndex, 1);
    });

    test('PayloadTooLarge surfaces payloadTooLarge and never sends', () async {
      encoder.throwOn = const PayloadTooLarge(actual: 100, cap: 50);
      await cubit.open([_note('a')]);
      peer.peers.add([_peer('p1')]);
      await _settle();

      await cubit.sendTo(_peer('p1'));

      expect(cubit.state.phase, ShareNearbyPhase.failed);
      expect(cubit.state.failure, ShareNearbyFailure.payloadTooLarge);
      expect(cubit.state.failureDetail, '100/50');
      expect(peer.actionLog.any((l) => l.startsWith('sendBytes:')), isFalse);
    });

    test('transfer failed event aborts the queue', () async {
      await cubit.open([_note('a'), _note('b')]);
      peer.peers.add([_peer('p1')]);
      await _settle();

      final sendFuture = cubit.sendTo(_peer('p1'));
      await _settle();
      peer.transfers.add(
        _evt(
          transferId: 'tx-1',
          peerId: 'p1',
          phase: TransferPhase.failed,
          errorMessage: 'oom',
        ),
      );
      await sendFuture;

      expect(cubit.state.phase, ShareNearbyPhase.failed);
      expect(cubit.state.failure, ShareNearbyFailure.transferFailed);
      expect(cubit.state.failureDetail, 'oom');
      expect(encoder.callCount, 1);
    });

    test('multi-note queue advances and completes when every transfer finishes', () async {
      await cubit.open([_note('a'), _note('b'), _note('c')]);
      peer.peers.add([_peer('p1')]);
      await _settle();

      final sendFuture = cubit.sendTo(_peer('p1'));

      for (final id in const ['tx-1', 'tx-2', 'tx-3']) {
        await _settle();
        peer.transfers.add(
          _evt(
            transferId: id,
            peerId: 'p1',
            phase: TransferPhase.completed,
            bytes: 100,
          ),
        );
      }
      await sendFuture;

      expect(encoder.encodedNoteIds, ['a', 'b', 'c']);
      expect(peer.actionLog.where((l) => l.startsWith('sendBytes:')).length, 3);
      expect(cubit.state.phase, ShareNearbyPhase.completed);
      expect(cubit.state.queueIndex, 3);
    });

    test('multi-note queue aborts on second transfer failure', () async {
      await cubit.open([_note('a'), _note('b'), _note('c')]);
      peer.peers.add([_peer('p1')]);
      await _settle();

      final sendFuture = cubit.sendTo(_peer('p1'));

      await _settle();
      peer.transfers.add(
        _evt(
          transferId: 'tx-1',
          peerId: 'p1',
          phase: TransferPhase.completed,
          bytes: 100,
        ),
      );
      await _settle();
      peer.transfers.add(
        _evt(
          transferId: 'tx-2',
          peerId: 'p1',
          phase: TransferPhase.failed,
          errorMessage: 'lost',
        ),
      );
      await sendFuture;

      expect(peer.actionLog.where((l) => l.startsWith('sendBytes:')).length, 2);
      expect(cubit.state.phase, ShareNearbyPhase.failed);
      expect(cubit.state.failure, ShareNearbyFailure.transferFailed);
      expect(cubit.state.queueIndex, 1);
    });
  });

  group('ShareNearbyCubit.cancel', () {
    test(
      'mid-transfer cancel asks the transport, surfaces cancelled, stops the service',
      () async {
        await cubit.open([_note('a')]);
        peer.peers.add([_peer('p1')]);
        await _settle();

        final sendFuture = cubit.sendTo(_peer('p1'));
        await _settle();
        peer.transfers.add(
          _evt(
            transferId: 'tx-1',
            peerId: 'p1',
            phase: TransferPhase.inProgress,
            bytes: 30,
          ),
        );
        await _settle();

        await cubit.cancel();
        await sendFuture;

        expect(peer.actionLog, contains('cancelTransfer:tx-1'));
        expect(peer.actionLog, contains('stop'));
        expect(cubit.state.phase, ShareNearbyPhase.failed);
        expect(cubit.state.failure, ShareNearbyFailure.transferCancelled);
      },
    );

    test('idempotent: a second cancel does not re-stop the service', () async {
      await cubit.open([_note('a')]);
      await _settle();
      await cubit.cancel();
      await cubit.cancel();

      expect(peer.actionLog.where((l) => l == 'stop').length, 1);
    });
  });

  group('ShareNearbyCubit.close', () {
    test('stops the service when called while sending', () async {
      await cubit.open([_note('a')]);
      peer.peers.add([_peer('p1')]);
      await _settle();

      final sendFuture = cubit.sendTo(_peer('p1'));
      await _settle();

      await cubit.close();
      await sendFuture;

      expect(peer.actionLog.where((l) => l == 'stop').length, 1);
    });
  });
}
