import 'dart:async';

import 'package:bloc/bloc.dart';

import 'package:noti_notes_app/models/note.dart';
import 'package:noti_notes_app/models/noti_identity.dart';
import 'package:noti_notes_app/services/share/peer_models.dart';
import 'package:noti_notes_app/services/share/peer_service.dart';
import 'package:noti_notes_app/services/share/share_codec.dart';
import 'package:noti_notes_app/services/share/share_models.dart';

import 'share_nearby_state.dart';

/// Drives the sender-side share sheet: discover peers, encode, send,
/// report progress. Permissions are gated by the caller before the sheet
/// opens (Spec 12); this cubit assumes the transport is allowed to start.
class ShareNearbyCubit extends Cubit<ShareNearbyState> {
  ShareNearbyCubit({
    required PeerService peerService,
    required ShareEncoder encoder,
    required NotiIdentity Function() identity,
  })  : _peer = peerService,
        _encoder = encoder,
        _identity = identity,
        super(const ShareNearbyState.discovering(<Note>[]));

  final PeerService _peer;
  final ShareEncoder _encoder;
  final NotiIdentity Function() _identity;

  StreamSubscription<List<DiscoveredPeer>>? _peerSub;
  StreamSubscription<TransferEvent>? _transferSub;
  Completer<void>? _activeTransfer;
  bool _started = false;

  Future<void> open(List<Note> notes) async {
    emit(ShareNearbyState.discovering(notes));
    try {
      await _peer.start(role: PeerRole.both, displayName: _identity().displayName);
      _started = true;
    } catch (e) {
      _emitFailed(ShareNearbyFailure.permissionStartFailed, '$e');
      return;
    }

    _peerSub = _peer.peerStream.listen((peers) {
      if (isClosed) return;
      if (state.phase == ShareNearbyPhase.discovering || state.phase == ShareNearbyPhase.sending) {
        emit(state.copyWith(peers: peers));
      }
    });

    _transferSub = _peer.transferStream.listen(_onTransferEvent);
  }

  Future<void> sendTo(DiscoveredPeer peer) async {
    if (state.phase != ShareNearbyPhase.discovering) return;
    if (state.queue.isEmpty) return;

    emit(
      state.copyWith(
        phase: ShareNearbyPhase.sending,
        activePeerId: peer.id,
        fraction: 0,
      ),
    );

    final sender = _identity();
    for (var i = state.queueIndex; i < state.queue.length; i++) {
      final OutgoingShare out;
      try {
        out = await _encoder.encode(note: state.queue[i], sender: sender);
      } on PayloadTooLarge catch (e) {
        _emitFailed(
          ShareNearbyFailure.payloadTooLarge,
          '${e.actual}/${e.cap}',
        );
        return;
      } catch (e) {
        _emitFailed(ShareNearbyFailure.encodeError, '$e');
        return;
      }

      final String transferId;
      try {
        transferId = await _peer.sendBytes(peer.id, out.bytes);
      } catch (e) {
        _emitFailed(ShareNearbyFailure.transferFailed, '$e');
        return;
      }

      final pending = Completer<void>();
      _activeTransfer = pending;
      emit(state.copyWith(activeTransferId: transferId, fraction: 0));

      try {
        await pending.future;
      } catch (_) {
        return;
      }

      if (isClosed) return;
      emit(
        state.copyWith(
          queueIndex: i + 1,
          fraction: 0,
          clearActiveTransfer: true,
        ),
      );
    }

    if (!isClosed) emit(state.copyWith(phase: ShareNearbyPhase.completed));
  }

  /// User-initiated tear-down. Idempotent. Aborts any in-flight transfer
  /// before stopping the transport so both sides see a `cancelled` event.
  Future<void> cancel() async {
    final activeId = state.activeTransferId;
    if (activeId != null) {
      try {
        await _peer.cancelTransfer(activeId);
      } catch (_) {}
    }

    final wasMidFlight =
        state.phase == ShareNearbyPhase.discovering || state.phase == ShareNearbyPhase.sending;
    if (wasMidFlight && !isClosed) {
      emit(
        state.copyWith(
          phase: ShareNearbyPhase.failed,
          failure: ShareNearbyFailure.transferCancelled,
          clearActiveTransfer: true,
        ),
      );
    }
    _settleActiveTransfer(error: const _TerminalAbort());

    await _shutdown();
  }

  @override
  Future<void> close() async {
    _settleActiveTransfer(error: const _TerminalAbort());
    await _shutdown();
    return super.close();
  }

  void _onTransferEvent(TransferEvent e) {
    if (isClosed) return;
    if (e.direction != TransferDirection.send) return;
    if (e.transferId != state.activeTransferId) return;

    switch (e.phase) {
      case TransferPhase.queued:
      case TransferPhase.inProgress:
        emit(state.copyWith(fraction: e.fraction));
      case TransferPhase.completed:
        emit(state.copyWith(fraction: 1));
        _settleActiveTransfer();
      case TransferPhase.cancelled:
        emit(
          state.copyWith(
            phase: ShareNearbyPhase.failed,
            failure: ShareNearbyFailure.transferCancelled,
            clearActiveTransfer: true,
          ),
        );
        _settleActiveTransfer(error: const _TerminalAbort());
      case TransferPhase.failed:
        emit(
          state.copyWith(
            phase: ShareNearbyPhase.failed,
            failure: ShareNearbyFailure.transferFailed,
            failureDetail: e.errorMessage,
            clearActiveTransfer: true,
          ),
        );
        _settleActiveTransfer(error: const _TerminalAbort());
    }
  }

  /// Resolve the in-flight `Completer` exactly once. Clearing the field
  /// before completing prevents a double-resolution `StateError` if both
  /// the user-cancel path and a native `cancelled` event race to settle
  /// the same completer.
  void _settleActiveTransfer({Object? error}) {
    final pending = _activeTransfer;
    if (pending == null) return;
    _activeTransfer = null;
    if (error == null) {
      pending.complete();
    } else {
      pending.completeError(error);
    }
  }

  void _emitFailed(ShareNearbyFailure failure, String? detail) {
    if (isClosed) return;
    emit(
      state.copyWith(
        phase: ShareNearbyPhase.failed,
        failure: failure,
        failureDetail: detail,
        clearActiveTransfer: true,
      ),
    );
  }

  Future<void> _shutdown() async {
    await _peerSub?.cancel();
    _peerSub = null;
    await _transferSub?.cancel();
    _transferSub = null;
    if (_started) {
      _started = false;
      try {
        await _peer.stop();
      } catch (_) {}
    }
  }
}

/// Internal sentinel used to unwind `sendTo`'s loop when a transfer
/// terminates non-successfully. Never escapes the cubit.
class _TerminalAbort implements Exception {
  const _TerminalAbort();
}
