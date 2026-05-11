import 'dart:async';

import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/models/received_share.dart';
import 'package:noti_notes_app/repositories/received_inbox/received_inbox_repository.dart';
import 'package:noti_notes_app/services/share/peer_models.dart';
import 'package:noti_notes_app/services/share/peer_service.dart';
import 'package:noti_notes_app/services/share/share_codec.dart';
import 'package:noti_notes_app/services/share/share_models.dart';

/// Owns the opt-in [PeerService.payloadStream] subscription for the
/// receive side (Spec 25). Per architecture invariant 3 the transport
/// stays idle until the user opens the inbox screen and taps "Receive a
/// shared note"; [stopReceiving] tears the subscription and the
/// transport down again.
///
/// Decode failures are surfaced on [events] and the bytes are dropped —
/// no inbox row is created and no asset bytes are persisted, so a
/// tampered or unsupported payload has no after-effects beyond a
/// transient UI message.
class InboxListenerService {
  InboxListenerService({
    required PeerService peer,
    required ShareDecoder decoder,
    required ReceivedInboxRepository inbox,
    required NotiIdentity Function() identity,
  })  : _peer = peer,
        _decoder = decoder,
        _inbox = inbox,
        _identity = identity;

  final PeerService _peer;
  final ShareDecoder _decoder;
  final ReceivedInboxRepository _inbox;
  final NotiIdentity Function() _identity;

  final StreamController<InboxListenerEvent> _events =
      StreamController<InboxListenerEvent>.broadcast();
  StreamSubscription<IncomingPayload>? _sub;
  bool _started = false;

  bool get isReceiving => _started;

  Stream<InboxListenerEvent> get events => _events.stream;

  Future<void> startReceiving() async {
    if (_started) return;
    try {
      await _peer.start(role: PeerRole.both, displayName: _identity().displayName);
    } catch (e) {
      _events.add(InboxListenerEvent.peerStartFailed('$e'));
      rethrow;
    }
    _started = true;
    _sub = _peer.payloadStream.listen(_onPayload);
  }

  Future<void> stopReceiving() async {
    await _sub?.cancel();
    _sub = null;
    if (!_started) return;
    _started = false;
    try {
      await _peer.stop();
    } catch (_) {
      // Stop is documented as idempotent and best-effort; surfacing this
      // would mask the user's intent (turn receiving off). Swallow.
    }
  }

  Future<void> dispose() async {
    await stopReceiving();
    await _events.close();
  }

  Future<void> _onPayload(IncomingPayload payload) async {
    final result = await _decoder.decode(payload.bytes);
    switch (result) {
      case DecodeOk(:final share):
        await _inbox.insert(
          ReceivedShare(
            shareId: share.shareId,
            receivedAt: DateTime.now().toUtc(),
            sender: share.sender,
            note: share.note,
            assets: share.assets,
            inboxRoot: share.inboxRoot,
          ),
        );
        _events.add(InboxListenerEvent.shareReceived(share.shareId));
      case DecodeUnsupportedVersion(:final version):
        _events.add(InboxListenerEvent.decodeRejected('unsupported_version:$version'));
      case DecodeSignatureInvalid():
        _events.add(const InboxListenerEvent.decodeRejected('signature_invalid'));
      case DecodeSizeExceeded(:final actual, :final cap):
        _events.add(InboxListenerEvent.decodeRejected('size_exceeded:$actual/$cap'));
      case DecodeMalformed(:final reason):
        _events.add(InboxListenerEvent.decodeRejected('malformed:$reason'));
    }
  }
}

/// Side-channel events from [InboxListenerService] that do not belong on
/// the cubit's primary state. UI surfaces these as transient SnackBars
/// and does not persist them. Sealed so consumers must `switch`
/// exhaustively.
sealed class InboxListenerEvent {
  const InboxListenerEvent();

  const factory InboxListenerEvent.shareReceived(String shareId) = ShareReceived;
  const factory InboxListenerEvent.decodeRejected(String reason) = DecodeRejected;
  const factory InboxListenerEvent.peerStartFailed(String detail) = PeerStartFailed;
}

class ShareReceived extends InboxListenerEvent {
  const ShareReceived(this.shareId);
  final String shareId;
}

class DecodeRejected extends InboxListenerEvent {
  const DecodeRejected(this.reason);
  final String reason;
}

class PeerStartFailed extends InboxListenerEvent {
  const PeerStartFailed(this.detail);
  final String detail;
}
