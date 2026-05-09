import 'package:equatable/equatable.dart';

import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/services/share/peer_models.dart';

enum ShareNearbyPhase { discovering, sending, completed, failed }

enum ShareNearbyFailure {
  permissionStartFailed,
  payloadTooLarge,
  encodeError,
  transferCancelled,
  transferFailed,
}

class ShareNearbyState extends Equatable {
  const ShareNearbyState({
    required this.phase,
    required this.queue,
    required this.queueIndex,
    required this.peers,
    required this.fraction,
    this.activeTransferId,
    this.activePeerId,
    this.failure,
    this.failureDetail,
  });

  const ShareNearbyState.discovering(this.queue)
      : phase = ShareNearbyPhase.discovering,
        queueIndex = 0,
        peers = const <DiscoveredPeer>[],
        fraction = 0,
        activeTransferId = null,
        activePeerId = null,
        failure = null,
        failureDetail = null;

  final ShareNearbyPhase phase;
  final List<Note> queue;
  final int queueIndex;
  final List<DiscoveredPeer> peers;
  final double fraction;
  final String? activeTransferId;
  final String? activePeerId;
  final ShareNearbyFailure? failure;
  final String? failureDetail;

  ShareNearbyState copyWith({
    ShareNearbyPhase? phase,
    List<Note>? queue,
    int? queueIndex,
    List<DiscoveredPeer>? peers,
    double? fraction,
    String? activeTransferId,
    String? activePeerId,
    ShareNearbyFailure? failure,
    String? failureDetail,
    bool clearActiveTransfer = false,
    bool clearFailure = false,
  }) {
    return ShareNearbyState(
      phase: phase ?? this.phase,
      queue: queue ?? this.queue,
      queueIndex: queueIndex ?? this.queueIndex,
      peers: peers ?? this.peers,
      fraction: fraction ?? this.fraction,
      activeTransferId: clearActiveTransfer ? null : (activeTransferId ?? this.activeTransferId),
      activePeerId: clearActiveTransfer ? null : (activePeerId ?? this.activePeerId),
      failure: clearFailure ? null : (failure ?? this.failure),
      failureDetail: clearFailure ? null : (failureDetail ?? this.failureDetail),
    );
  }

  @override
  List<Object?> get props => [
        phase,
        queue,
        queueIndex,
        peers,
        fraction,
        activeTransferId,
        activePeerId,
        failure,
        failureDetail,
      ];
}
