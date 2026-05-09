import 'dart:async';

import 'package:noti_notes_app/services/share/peer_models.dart';
import 'package:noti_notes_app/services/share/peer_service.dart';

/// Fully scriptable [PeerService] for unit tests.
///
/// Push events through the public controllers; assert against the
/// `actionLog` of methods the system-under-test invoked.
class FakePeerService implements PeerService {
  final StreamController<List<DiscoveredPeer>> peers =
      StreamController<List<DiscoveredPeer>>.broadcast();
  final StreamController<IncomingInvite> invites = StreamController<IncomingInvite>.broadcast();
  final StreamController<IncomingPayload> payloads = StreamController<IncomingPayload>.broadcast();
  final StreamController<TransferEvent> transfers = StreamController<TransferEvent>.broadcast();

  final List<String> actionLog = <String>[];
  bool _active = false;
  int _idCounter = 0;

  PeerStartFailed? failOnStart;

  @override
  bool get isActive => _active;

  @override
  Stream<List<DiscoveredPeer>> get peerStream => peers.stream;

  @override
  Stream<IncomingInvite> get inviteStream => invites.stream;

  @override
  Stream<IncomingPayload> get payloadStream => payloads.stream;

  @override
  Stream<TransferEvent> get transferStream => transfers.stream;

  @override
  Future<void> start({required PeerRole role, required String displayName}) async {
    actionLog.add('start:${role.name}:$displayName');
    final fail = failOnStart;
    if (fail != null) throw fail;
    if (_active) throw const PeerStartFailed.alreadyActive();
    _active = true;
  }

  @override
  Future<void> stop() async {
    actionLog.add('stop');
    _active = false;
    peers.add(const <DiscoveredPeer>[]);
  }

  @override
  Future<void> invite(String peerId) async {
    actionLog.add('invite:$peerId');
  }

  @override
  Future<void> acceptInvite(String inviteId) async {
    actionLog.add('acceptInvite:$inviteId');
  }

  @override
  Future<void> rejectInvite(String inviteId) async {
    actionLog.add('rejectInvite:$inviteId');
  }

  @override
  Future<String> sendBytes(String peerId, List<int> bytes) async {
    if (bytes.length > peerPayloadMaxBytes) {
      throw ArgumentError('payload too large');
    }
    final id = 'tx-${++_idCounter}';
    actionLog.add('sendBytes:$peerId:${bytes.length}:$id');
    return id;
  }

  @override
  Future<String> sendFile(String peerId, String filePath) async {
    final id = 'tx-${++_idCounter}';
    actionLog.add('sendFile:$peerId:$filePath:$id');
    return id;
  }

  @override
  Future<void> cancelTransfer(String transferId) async {
    actionLog.add('cancelTransfer:$transferId');
  }

  @override
  Future<void> disconnect(String peerId) async {
    actionLog.add('disconnect:$peerId');
  }

  Future<void> dispose() async {
    await peers.close();
    await invites.close();
    await payloads.close();
    await transfers.close();
  }
}
