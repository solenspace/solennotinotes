import 'package:equatable/equatable.dart';

/// Connection state of a [DiscoveredPeer]. Mirrors the lifecycle the native
/// platforms expose; the share UI groups `inviting` and `accepting` together
/// as "in flight".
enum PeerConnectionState { found, inviting, accepting, connected, disconnected }

/// A device the user can attempt to share with. Identity is the opaque
/// platform-assigned id; [displayName] is what the receiver chose for
/// themselves.
class DiscoveredPeer extends Equatable {
  const DiscoveredPeer({
    required this.id,
    required this.displayName,
    required this.state,
  });

  final String id;
  final String displayName;
  final PeerConnectionState state;

  DiscoveredPeer copyWith({PeerConnectionState? state}) => DiscoveredPeer(
        id: id,
        displayName: displayName,
        state: state ?? this.state,
      );

  @override
  List<Object?> get props => [id, displayName, state];
}

/// Inbound connection request from another peer. The receiver answers with
/// [PeerService.acceptInvite] / [PeerService.rejectInvite].
class IncomingInvite extends Equatable {
  const IncomingInvite({
    required this.id,
    required this.peerId,
    required this.peerName,
  });

  final String id;
  final String peerId;
  final String peerName;

  @override
  List<Object?> get props => [id, peerId, peerName];
}

/// A complete byte payload received from a peer. Big payloads (assets) are
/// delivered through the file path variant by the native side; this in-memory
/// form is for the share-envelope itself.
class IncomingPayload extends Equatable {
  const IncomingPayload({
    required this.peerId,
    required this.bytes,
    this.filePath,
  });

  final String peerId;
  final List<int> bytes;

  /// When non-null the payload is too large to materialize in memory and the
  /// native side has streamed it to this temp file. Caller owns the file.
  final String? filePath;

  @override
  List<Object?> get props => [peerId, bytes, filePath];
}

enum TransferDirection { send, receive }

enum TransferPhase { queued, inProgress, completed, cancelled, failed }

/// Single tick of progress for an in-flight transfer. Both sides emit these
/// — the share UI listens to the union and matches by [transferId].
class TransferEvent extends Equatable {
  const TransferEvent({
    required this.transferId,
    required this.peerId,
    required this.direction,
    required this.phase,
    required this.bytes,
    required this.total,
    this.errorMessage,
  });

  final String transferId;
  final String peerId;
  final TransferDirection direction;
  final TransferPhase phase;
  final int bytes;
  final int total;
  final String? errorMessage;

  double get fraction => total <= 0 ? 0 : (bytes / total).clamp(0.0, 1.0).toDouble();

  bool get isTerminal =>
      phase == TransferPhase.completed ||
      phase == TransferPhase.cancelled ||
      phase == TransferPhase.failed;

  @override
  List<Object?> get props => [transferId, peerId, direction, phase, bytes, total, errorMessage];
}

/// Failure surfaces that callers care about. Anything else bubbles as a raw
/// [PlatformException] from the channel.
sealed class PeerStartFailed implements Exception {
  const PeerStartFailed();

  const factory PeerStartFailed.permissionDenied(String which) = _PermissionDenied;
  const factory PeerStartFailed.alreadyActive() = _AlreadyActive;
  const factory PeerStartFailed.platformUnsupported() = _PlatformUnsupported;
  const factory PeerStartFailed.pluginInitFailure(String message) = _PluginInitFailure;
}

class _PermissionDenied extends PeerStartFailed {
  const _PermissionDenied(this.permission);
  final String permission;
  @override
  String toString() => 'PeerStartFailed.permissionDenied($permission)';
}

class _AlreadyActive extends PeerStartFailed {
  const _AlreadyActive();
  @override
  String toString() => 'PeerStartFailed.alreadyActive';
}

class _PlatformUnsupported extends PeerStartFailed {
  const _PlatformUnsupported();
  @override
  String toString() => 'PeerStartFailed.platformUnsupported';
}

class _PluginInitFailure extends PeerStartFailed {
  const _PluginInitFailure(this.message);
  final String message;
  @override
  String toString() => 'PeerStartFailed.pluginInitFailure: $message';
}
