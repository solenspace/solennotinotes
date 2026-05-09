import Flutter
import Foundation
import MultipeerConnectivity

/// Bridges spec 22 `PeerService` to Apple's MultipeerConnectivity framework.
///
/// Channels (must match `lib/services/share/channel_peer_service.dart`):
/// - method `noti.peer/control` — start/stop/invite/accept/reject/sendBytes/sendFile/cancel/disconnect
/// - event  `noti.peer/peers` — list of discovered + connected peers
/// - event  `noti.peer/invites` — inbound invitations awaiting accept/reject
/// - event  `noti.peer/payloads` — received bytes / streamed files
/// - event  `noti.peer/transfers` — per-transfer progress for both directions
public final class PeerServicePlugin: NSObject {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = PeerServicePlugin()
        let control = FlutterMethodChannel(
            name: "noti.peer/control",
            binaryMessenger: registrar.messenger()
        )
        control.setMethodCallHandler(plugin.handle)
        plugin.peersChannel = FlutterEventChannel(
            name: "noti.peer/peers", binaryMessenger: registrar.messenger())
        plugin.invitesChannel = FlutterEventChannel(
            name: "noti.peer/invites", binaryMessenger: registrar.messenger())
        plugin.payloadsChannel = FlutterEventChannel(
            name: "noti.peer/payloads", binaryMessenger: registrar.messenger())
        plugin.transfersChannel = FlutterEventChannel(
            name: "noti.peer/transfers", binaryMessenger: registrar.messenger())
        plugin.peersChannel?.setStreamHandler(plugin.peersHandler)
        plugin.invitesChannel?.setStreamHandler(plugin.invitesHandler)
        plugin.payloadsChannel?.setStreamHandler(plugin.payloadsHandler)
        plugin.transfersChannel?.setStreamHandler(plugin.transfersHandler)
    }

    // Channels
    private var peersChannel: FlutterEventChannel?
    private var invitesChannel: FlutterEventChannel?
    private var payloadsChannel: FlutterEventChannel?
    private var transfersChannel: FlutterEventChannel?
    fileprivate let peersHandler = SinkHandler()
    fileprivate let invitesHandler = SinkHandler()
    fileprivate let payloadsHandler = SinkHandler()
    fileprivate let transfersHandler = SinkHandler()

    // MultipeerConnectivity state — recreated on each start().
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var localPeerID: MCPeerID?
    private var serviceType: String = "noti-share"

    private var peersById: [String: MCPeerID] = [:]
    private var stateById: [String: String] = [:]

    private var pendingInvites: [String: (Bool, MCSession?) -> Void] = [:]
    private var inviteToPeer: [String: MCPeerID] = [:]

    private var sendProgress: [String: Progress] = [:]
    private var receiveProgress: [String: Progress] = [:]
    private var sendObservers: [String: NSKeyValueObservation] = [:]
    private var receiveObservers: [String: NSKeyValueObservation] = [:]
    private var sendTransferIdByPeer: [String: String] = [:]
    /// Maps `"<peerId>|<resourceName>"` to the transferId we minted on the
    /// receive side. Replaces the previous `objc_setAssociatedObject` trick,
    /// which used a single file-scope key and could mis-attribute simultaneous
    /// transfers.
    private var receiveTransferIds: [String: String] = [:]

    // MARK: - Method dispatch

    fileprivate func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start": start(call.arguments, result: result)
        case "stop": stop(result: result)
        case "invite": invite(call.arguments, result: result)
        case "acceptInvite": acceptInvite(call.arguments, result: result)
        case "rejectInvite": rejectInvite(call.arguments, result: result)
        case "sendBytes": sendBytes(call.arguments, result: result)
        case "sendFile": sendFile(call.arguments, result: result)
        case "cancelTransfer": cancelTransfer(call.arguments, result: result)
        case "disconnect": disconnect(call.arguments, result: result)
        default: result(FlutterMethodNotImplemented)
        }
    }

    private func start(_ args: Any?, result: @escaping FlutterResult) {
        guard let map = args as? [String: Any],
              let role = map["role"] as? String,
              let displayName = map["displayName"] as? String,
              let serviceTypeArg = map["serviceType"] as? String
        else {
            result(FlutterError(code: "bad_args", message: "start: missing arguments", details: nil))
            return
        }
        if session != nil {
            result(FlutterError(code: "already_active", message: "PeerService already running", details: nil))
            return
        }

        serviceType = serviceTypeArg
        let peerID = MCPeerID(displayName: displayName.isEmpty ? "noti" : displayName)
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        self.localPeerID = peerID

        if role == "advertise" || role == "both" {
            let adv = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceTypeArg)
            adv.delegate = self
            adv.startAdvertisingPeer()
            advertiser = adv
        }
        if role == "discover" || role == "both" {
            let br = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceTypeArg)
            br.delegate = self
            br.startBrowsingForPeers()
            browser = br
        }
        emitPeers()
        result(nil)
    }

    private func stop(result: @escaping FlutterResult) {
        // Invalidate KVO observers BEFORE clearing the progress dictionaries,
        // otherwise a callback already queued on the main thread can fire
        // against a half-cleared state.
        sendObservers.values.forEach { $0.invalidate() }
        receiveObservers.values.forEach { $0.invalidate() }
        sendObservers.removeAll()
        receiveObservers.removeAll()

        advertiser?.delegate = nil
        browser?.delegate = nil
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.delegate = nil
        session?.disconnect()

        for (_, p) in sendProgress { p.cancel() }
        for (_, p) in receiveProgress { p.cancel() }
        sendProgress.removeAll()
        receiveProgress.removeAll()
        sendTransferIdByPeer.removeAll()
        receiveTransferIds.removeAll()
        peersById.removeAll()
        stateById.removeAll()
        pendingInvites.removeAll()
        inviteToPeer.removeAll()
        advertiser = nil
        browser = nil
        session = nil
        localPeerID = nil
        peersHandler.send([])
        result(nil)
    }

    private func invite(_ args: Any?, result: @escaping FlutterResult) {
        guard let map = args as? [String: Any],
              let peerId = map["peerId"] as? String,
              let peer = peersById[peerId],
              let session = session,
              let browser = browser
        else {
            result(FlutterError(code: "no_peer", message: "Unknown peer or not browsing", details: nil))
            return
        }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
        stateById[peerId] = "inviting"
        emitPeers()
        result(nil)
    }

    private func acceptInvite(_ args: Any?, result: @escaping FlutterResult) {
        guard let map = args as? [String: Any],
              let inviteId = map["inviteId"] as? String,
              let handler = pendingInvites.removeValue(forKey: inviteId)
        else {
            result(FlutterError(code: "no_invite", message: "Unknown invite id", details: nil))
            return
        }
        handler(true, session)
        if let peer = inviteToPeer.removeValue(forKey: inviteId), let pid = peersById.first(where: { $0.value == peer })?.key {
            stateById[pid] = "accepting"
            emitPeers()
        }
        result(nil)
    }

    private func rejectInvite(_ args: Any?, result: @escaping FlutterResult) {
        guard let map = args as? [String: Any],
              let inviteId = map["inviteId"] as? String,
              let handler = pendingInvites.removeValue(forKey: inviteId)
        else {
            result(FlutterError(code: "no_invite", message: "Unknown invite id", details: nil))
            return
        }
        handler(false, nil)
        inviteToPeer.removeValue(forKey: inviteId)
        result(nil)
    }

    private func sendBytes(_ args: Any?, result: @escaping FlutterResult) {
        guard let map = args as? [String: Any],
              let peerId = map["peerId"] as? String,
              let peer = peersById[peerId],
              let session = session,
              let bytes = map["bytes"] as? FlutterStandardTypedData
        else {
            result(FlutterError(code: "bad_args", message: "sendBytes args", details: nil))
            return
        }
        let transferId = UUID().uuidString
        let total = bytes.data.count
        do {
            try session.send(bytes.data, toPeers: [peer], with: .reliable)
            transfersHandler.send(transferEvent(transferId: transferId, peerId: peerId, direction: "send", phase: "completed", bytes: total, total: total))
            result(transferId)
        } catch {
            transfersHandler.send(transferEvent(transferId: transferId, peerId: peerId, direction: "send", phase: "failed", bytes: 0, total: total, error: error.localizedDescription))
            result(FlutterError(code: "send_failed", message: error.localizedDescription, details: nil))
        }
    }

    private func sendFile(_ args: Any?, result: @escaping FlutterResult) {
        guard let map = args as? [String: Any],
              let peerId = map["peerId"] as? String,
              let peer = peersById[peerId],
              let session = session,
              let path = map["path"] as? String
        else {
            result(FlutterError(code: "bad_args", message: "sendFile args", details: nil))
            return
        }
        let url = URL(fileURLWithPath: path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attrs[.size] as? Int
        else {
            result(FlutterError(code: "no_file", message: "Cannot stat file", details: nil))
            return
        }
        if let cap = map["maxBytes"] as? Int, fileSize > cap {
            result(FlutterError(code: "too_large", message: "File exceeds size cap", details: nil))
            return
        }
        let transferId = UUID().uuidString
        let resourceName = url.lastPathComponent
        sendTransferIdByPeer["\(peerId)|\(resourceName)"] = transferId
        let progress = session.sendResource(at: url, withName: resourceName, toPeer: peer) { [weak self] err in
            guard let self = self else { return }
            let phase = err == nil ? "completed" : "failed"
            self.transfersHandler.send(self.transferEvent(
                transferId: transferId, peerId: peerId, direction: "send",
                phase: phase, bytes: fileSize, total: fileSize,
                error: err?.localizedDescription))
            self.sendObservers[transferId]?.invalidate()
            self.sendObservers.removeValue(forKey: transferId)
            self.sendProgress.removeValue(forKey: transferId)
        }
        if let progress = progress {
            sendProgress[transferId] = progress
            sendObservers[transferId] = progress.observe(\.fractionCompleted) { [weak self] p, _ in
                guard let self = self else { return }
                let bytes = Int(Double(fileSize) * p.fractionCompleted)
                self.transfersHandler.send(self.transferEvent(
                    transferId: transferId, peerId: peerId, direction: "send",
                    phase: "inProgress", bytes: bytes, total: fileSize))
            }
        }
        result(transferId)
    }

    private func cancelTransfer(_ args: Any?, result: @escaping FlutterResult) {
        guard let map = args as? [String: Any], let transferId = map["transferId"] as? String else {
            result(FlutterError(code: "bad_args", message: "cancelTransfer", details: nil))
            return
        }
        sendProgress[transferId]?.cancel()
        receiveProgress[transferId]?.cancel()
        result(nil)
    }

    private func disconnect(_ args: Any?, result: @escaping FlutterResult) {
        // Multipeer does not expose per-peer disconnect from one side without tearing the
        // whole session. This call is a stub that disconnects the entire session.
        session?.disconnect()
        result(nil)
    }

    // MARK: - Helpers

    private func peerKey(for peer: MCPeerID) -> String {
        // Deterministic id reused across browse/state cycles.
        return "\(peer.displayName)#\(peer.hash)"
    }

    fileprivate func emitPeers() {
        let list = peersById.map { (id, peer) -> [String: Any] in
            return [
                "id": id,
                "displayName": peer.displayName,
                "state": stateById[id] ?? "found",
            ]
        }
        peersHandler.send(list)
    }

    fileprivate func transferEvent(
        transferId: String, peerId: String, direction: String, phase: String,
        bytes: Int, total: Int, error: String? = nil
    ) -> [String: Any] {
        var ev: [String: Any] = [
            "transferId": transferId,
            "peerId": peerId,
            "direction": direction,
            "phase": phase,
            "bytes": bytes,
            "total": total,
        ]
        if let e = error { ev["error"] = e }
        return ev
    }
}

// MARK: - MCSessionDelegate

extension PeerServicePlugin: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let id = peerKey(for: peerID)
        peersById[id] = peerID
        switch state {
        case .notConnected: stateById[id] = "disconnected"
        case .connecting: stateById[id] = "accepting"
        case .connected: stateById[id] = "connected"
        @unknown default: stateById[id] = "found"
        }
        emitPeers()
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let id = peerKey(for: peerID)
        peersById[id] = peerID
        payloadsHandler.send([
            "peerId": id,
            "bytes": FlutterStandardTypedData(bytes: data),
        ])
    }

    public func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        let id = peerKey(for: peerID)
        let transferId = UUID().uuidString
        receiveProgress[transferId] = progress
        receiveTransferIds["\(id)|\(resourceName)"] = transferId
        receiveObservers[transferId] = progress.observe(\.fractionCompleted) { [weak self] p, _ in
            guard let self = self,
                  self.receiveProgress[transferId] != nil
            else { return }
            self.transfersHandler.send(self.transferEvent(
                transferId: transferId, peerId: id, direction: "receive",
                phase: "inProgress",
                bytes: Int(Double(p.totalUnitCount) * p.fractionCompleted),
                total: Int(p.totalUnitCount)))
        }
    }

    public func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        let id = peerKey(for: peerID)
        let key = "\(id)|\(resourceName)"
        let transferId = receiveTransferIds.removeValue(forKey: key) ?? UUID().uuidString
        let total = Int(receiveProgress[transferId]?.totalUnitCount ?? 0)
        let phase: String
        if let err = error {
            phase = err.localizedDescription.contains("cancel") ? "cancelled" : "failed"
        } else {
            phase = "completed"
        }
        transfersHandler.send(transferEvent(
            transferId: transferId, peerId: id, direction: "receive",
            phase: phase, bytes: total, total: total,
            error: error?.localizedDescription))
        receiveObservers[transferId]?.invalidate()
        receiveObservers.removeValue(forKey: transferId)
        receiveProgress.removeValue(forKey: transferId)
        if phase == "completed", let localURL = localURL {
            payloadsHandler.send([
                "peerId": id,
                "bytes": FlutterStandardTypedData(bytes: Data()),
                "filePath": localURL.path,
            ])
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Streams are unused — spec 22 transports bytes + files.
        stream.close()
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension PeerServicePlugin: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let id = peerKey(for: peerID)
        peersById[id] = peerID
        if stateById[id] == nil { stateById[id] = "found" }
        emitPeers()
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        let id = peerKey(for: peerID)
        peersById.removeValue(forKey: id)
        stateById.removeValue(forKey: id)
        emitPeers()
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension PeerServicePlugin: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let id = peerKey(for: peerID)
        peersById[id] = peerID
        let inviteId = UUID().uuidString
        pendingInvites[inviteId] = invitationHandler
        inviteToPeer[inviteId] = peerID
        invitesHandler.send([
            "id": inviteId,
            "peerId": id,
            "peerName": peerID.displayName,
        ])
    }
}

// MARK: - SinkHandler

final class SinkHandler: NSObject, FlutterStreamHandler {
    private var sink: FlutterEventSink?
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
    func send(_ value: Any) {
        DispatchQueue.main.async { [weak self] in self?.sink?(value) }
    }
}
