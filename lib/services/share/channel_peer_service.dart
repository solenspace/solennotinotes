import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';

import 'package:noti_notes_app/services/permissions/permission_result.dart';
import 'package:noti_notes_app/services/permissions/permissions_service.dart';

import 'peer_models.dart';
import 'peer_service.dart';

const _serviceType = 'noti-share';

const _controlChannel = MethodChannel('noti.peer/control');
const _peersChannel = EventChannel('noti.peer/peers');
const _invitesChannel = EventChannel('noti.peer/invites');
const _payloadsChannel = EventChannel('noti.peer/payloads');
const _transfersChannel = EventChannel('noti.peer/transfers');

/// Concrete [PeerService] talking to the native iOS Multipeer plugin and
/// Android Nearby Connections plugin via platform channels. The channels are
/// registered in `ios/Runner/AppDelegate.swift` and
/// `android/app/src/main/kotlin/.../MainActivity.kt`.
class ChannelPeerService implements PeerService {
  ChannelPeerService({
    required PermissionsService permissions,
    @visibleForTesting MethodChannel? control,
    @visibleForTesting EventChannel? peers,
    @visibleForTesting EventChannel? invites,
    @visibleForTesting EventChannel? payloads,
    @visibleForTesting EventChannel? transfers,
  })  : _permissions = permissions,
        _control = control ?? _controlChannel,
        _peers = peers ?? _peersChannel,
        _invites = invites ?? _invitesChannel,
        _payloads = payloads ?? _payloadsChannel,
        _transfers = transfers ?? _transfersChannel;

  final PermissionsService _permissions;
  final MethodChannel _control;
  final EventChannel _peers;
  final EventChannel _invites;
  final EventChannel _payloads;
  final EventChannel _transfers;

  final StreamController<List<DiscoveredPeer>> _peerController =
      StreamController<List<DiscoveredPeer>>.broadcast();
  final StreamController<IncomingInvite> _inviteController =
      StreamController<IncomingInvite>.broadcast();
  final StreamController<IncomingPayload> _payloadController =
      StreamController<IncomingPayload>.broadcast();
  final StreamController<TransferEvent> _transferController =
      StreamController<TransferEvent>.broadcast();

  StreamSubscription<dynamic>? _peerSub;
  StreamSubscription<dynamic>? _inviteSub;
  StreamSubscription<dynamic>? _payloadSub;
  StreamSubscription<dynamic>? _transferSub;

  bool _active = false;
  bool _starting = false;

  @override
  bool get isActive => _active;

  @override
  Stream<List<DiscoveredPeer>> get peerStream => _peerController.stream;

  @override
  Stream<IncomingInvite> get inviteStream => _inviteController.stream;

  @override
  Stream<IncomingPayload> get payloadStream => _payloadController.stream;

  @override
  Stream<TransferEvent> get transferStream => _transferController.stream;

  @override
  Future<void> start({required PeerRole role, required String displayName}) async {
    if (_active || _starting) {
      throw const PeerStartFailed.alreadyActive();
    }
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      throw const PeerStartFailed.platformUnsupported();
    }

    _starting = true;
    try {
      await _ensurePermissions();

      _peerSub = _peers.receiveBroadcastStream().listen(_onPeerEvent);
      _inviteSub = _invites.receiveBroadcastStream().listen(_onInviteEvent);
      _payloadSub = _payloads.receiveBroadcastStream().listen(_onPayloadEvent);
      _transferSub = _transfers.receiveBroadcastStream().listen(_onTransferEvent);

      try {
        await _control.invokeMethod<void>('start', <String, Object?>{
          'role': role.name,
          'displayName': displayName,
          'serviceType': _serviceType,
        });
        _active = true;
      } on PlatformException catch (e) {
        await _cancelStreams();
        throw PeerStartFailed.pluginInitFailure(e.message ?? e.code);
      }
    } finally {
      _starting = false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_active) return;
    // Cancel native event subscriptions BEFORE flipping `_active` so any
    // in-flight events emitted during teardown are dropped instead of leaking
    // into broadcast controllers that downstream listeners may already have
    // detached from. (flutter-expert review, 2026-05-09)
    await _cancelStreams();
    _active = false;
    try {
      await _control.invokeMethod<void>('stop');
    } on PlatformException {
      // Best-effort: even if native stop fails, the local streams are gone.
    }
    _peerController.add(const <DiscoveredPeer>[]);
  }

  Future<void> _cancelStreams() async {
    await _peerSub?.cancel();
    await _inviteSub?.cancel();
    await _payloadSub?.cancel();
    await _transferSub?.cancel();
    _peerSub = null;
    _inviteSub = null;
    _payloadSub = null;
    _transferSub = null;
  }

  Future<void> _ensurePermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _requireOrThrow('bluetoothScan', _permissions.requestBluetoothScan);
      await _requireOrThrow('bluetoothConnect', _permissions.requestBluetoothConnect);
      await _requireOrThrow('bluetoothAdvertise', _permissions.requestBluetoothAdvertise);
      await _requireOrThrow('nearbyWifiDevices', _permissions.requestNearbyWifiDevices);
    } else {
      // iOS Multipeer relies on local-network + Bluetooth usage strings in
      // Info.plist; runtime gating is handled by the OS when the user first
      // sees the share sheet. We still surface the connect permission so the
      // permission wrapper has parity with Android.
      await _requireOrThrow('bluetoothConnect', _permissions.requestBluetoothConnect);
    }
  }

  Future<void> _requireOrThrow(
    String name,
    Future<PermissionResult> Function() request,
  ) async {
    final result = await request();
    if (!result.isUsable) {
      throw PeerStartFailed.permissionDenied(name);
    }
  }

  @override
  Future<void> invite(String peerId) {
    return _control.invokeMethod<void>('invite', <String, Object?>{'peerId': peerId});
  }

  @override
  Future<void> acceptInvite(String inviteId) {
    return _control.invokeMethod<void>('acceptInvite', <String, Object?>{'inviteId': inviteId});
  }

  @override
  Future<void> rejectInvite(String inviteId) {
    return _control.invokeMethod<void>('rejectInvite', <String, Object?>{'inviteId': inviteId});
  }

  @override
  Future<String> sendBytes(String peerId, List<int> bytes) async {
    if (bytes.length > peerPayloadMaxBytes) {
      throw ArgumentError(
        'Payload of ${bytes.length} bytes exceeds ${peerPayloadMaxBytes ~/ (1024 * 1024)} MB cap',
      );
    }
    final id = await _control.invokeMethod<String>('sendBytes', <String, Object?>{
      'peerId': peerId,
      'bytes': Uint8List.fromList(bytes),
    });
    if (id == null) {
      throw StateError('Native sendBytes returned no transferId');
    }
    return id;
  }

  @override
  Future<String> sendFile(String peerId, String filePath) async {
    final id = await _control.invokeMethod<String>('sendFile', <String, Object?>{
      'peerId': peerId,
      'path': filePath,
      'maxBytes': peerPayloadMaxBytes,
    });
    if (id == null) {
      throw StateError('Native sendFile returned no transferId');
    }
    return id;
  }

  @override
  Future<void> cancelTransfer(String transferId) {
    return _control.invokeMethod<void>('cancelTransfer', <String, Object?>{
      'transferId': transferId,
    });
  }

  @override
  Future<void> disconnect(String peerId) {
    return _control.invokeMethod<void>('disconnect', <String, Object?>{'peerId': peerId});
  }

  // --- Event decoding ----------------------------------------------------

  void _onPeerEvent(dynamic event) {
    if (event is! List) return;
    final peers = <DiscoveredPeer>[];
    for (final raw in event) {
      if (raw is! Map) continue;
      final id = raw['id'];
      final name = raw['displayName'];
      final state = raw['state'];
      if (id is! String || name is! String) continue;
      peers.add(
        DiscoveredPeer(
          id: id,
          displayName: name,
          state: _decodeState(state is String ? state : 'found'),
        ),
      );
    }
    _peerController.add(peers);
  }

  PeerConnectionState _decodeState(String raw) {
    return switch (raw) {
      'inviting' => PeerConnectionState.inviting,
      'accepting' => PeerConnectionState.accepting,
      'connected' => PeerConnectionState.connected,
      'disconnected' => PeerConnectionState.disconnected,
      _ => PeerConnectionState.found,
    };
  }

  void _onInviteEvent(dynamic event) {
    if (event is! Map) return;
    final id = event['id'];
    final peerId = event['peerId'];
    final peerName = event['peerName'];
    if (id is String && peerId is String && peerName is String) {
      _inviteController.add(IncomingInvite(id: id, peerId: peerId, peerName: peerName));
    }
  }

  void _onPayloadEvent(dynamic event) {
    if (event is! Map) return;
    final peerId = event['peerId'];
    if (peerId is! String) return;
    final bytes = event['bytes'];
    final filePath = event['filePath'];
    _payloadController.add(
      IncomingPayload(
        peerId: peerId,
        bytes: bytes is List<int>
            ? bytes
            : (bytes is Uint8List ? List<int>.from(bytes) : const <int>[]),
        filePath: filePath is String ? filePath : null,
      ),
    );
  }

  void _onTransferEvent(dynamic event) {
    if (event is! Map) return;
    final transferId = event['transferId'];
    final peerId = event['peerId'];
    final direction = event['direction'];
    final phase = event['phase'];
    final bytes = event['bytes'];
    final total = event['total'];
    if (transferId is! String || peerId is! String) return;
    _transferController.add(
      TransferEvent(
        transferId: transferId,
        peerId: peerId,
        direction: direction == 'send' ? TransferDirection.send : TransferDirection.receive,
        phase: _decodePhase(phase is String ? phase : 'inProgress'),
        bytes: bytes is int ? bytes : 0,
        total: total is int ? total : 0,
        errorMessage: event['error'] is String ? event['error'] as String : null,
      ),
    );
  }

  TransferPhase _decodePhase(String raw) {
    return switch (raw) {
      'queued' => TransferPhase.queued,
      'completed' => TransferPhase.completed,
      'cancelled' => TransferPhase.cancelled,
      'failed' => TransferPhase.failed,
      _ => TransferPhase.inProgress,
    };
  }
}
