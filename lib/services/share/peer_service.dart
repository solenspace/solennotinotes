import 'peer_models.dart';

/// What the local device does while [PeerService] is active.
enum PeerRole {
  /// Visible to scanners but does not browse for peers itself.
  advertise,

  /// Browses for peers but is not visible.
  discover,

  /// Both — the default mode for the share flow so two users can find each
  /// other regardless of who initiated.
  both,
}

/// Hard ceiling on a single payload, mirroring architecture invariant 11.
/// The transport rejects sends past this limit; the codec (spec 23) keeps
/// envelopes well under it.
const int peerPayloadMaxBytes = 50 * 1024 * 1024;

/// Typed wrapper over the platform P2P transport. Discovery, advertising,
/// invitations, byte and file transfers — all flow through this contract so
/// no other layer imports the native channels or any third-party plugin.
///
/// Lifecycle is opt-in (architecture invariant 3): nothing scans or
/// advertises until the share UI calls [start]; everything stops on [stop].
abstract class PeerService {
  /// Acquire permissions and bring the transport up. Throws
  /// [PeerStartFailed] when permissions are missing or the underlying
  /// platform layer cannot initialize.
  Future<void> start({required PeerRole role, required String displayName});

  /// Tear the transport down. Cancels in-flight transfers, drops all peer
  /// state, and closes underlying sockets/sessions. Idempotent.
  Future<void> stop();

  /// Snapshot stream of currently-visible peers. Emits the latest list on
  /// every change. Empty list while [isActive] is false.
  Stream<List<DiscoveredPeer>> get peerStream;

  /// Inbound connection requests waiting on [acceptInvite] / [rejectInvite].
  Stream<IncomingInvite> get inviteStream;

  /// Complete payloads delivered by connected peers.
  Stream<IncomingPayload> get payloadStream;

  /// Per-transfer progress for both directions. Terminal events are
  /// guaranteed exactly once per [TransferEvent.transferId].
  Stream<TransferEvent> get transferStream;

  /// Ask [peerId] to connect. The remote side sees an [IncomingInvite].
  Future<void> invite(String peerId);

  /// Accept a previously-emitted [IncomingInvite].
  Future<void> acceptInvite(String inviteId);

  /// Decline a previously-emitted [IncomingInvite]. The other side gets a
  /// disconnected state on its peer.
  Future<void> rejectInvite(String inviteId);

  /// Send an in-memory byte buffer. Returns the transfer id used in
  /// [transferStream]. Throws [ArgumentError] when bytes exceed
  /// [peerPayloadMaxBytes].
  Future<String> sendBytes(String peerId, List<int> bytes);

  /// Send a file by path. Returns the transfer id used in [transferStream].
  /// Throws [ArgumentError] when the file size exceeds
  /// [peerPayloadMaxBytes].
  Future<String> sendFile(String peerId, String filePath);

  /// Abort an in-flight transfer (either direction). Both sides receive a
  /// [TransferPhase.cancelled] event.
  Future<void> cancelTransfer(String transferId);

  /// Drop the connection to a single peer without tearing the whole
  /// transport down.
  Future<void> disconnect(String peerId);

  /// True between a successful [start] and the next [stop].
  bool get isActive;
}
