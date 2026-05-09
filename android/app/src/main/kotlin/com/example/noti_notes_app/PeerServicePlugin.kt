package com.example.noti_notes_app

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.ConnectionsClient
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Bridges spec 22 PeerService to Google Nearby Connections.
 *
 * Channels mirror the iOS implementation in `ios/Runner/PeerServicePlugin.swift`
 * and the Dart [ChannelPeerService] consumer.
 */
class PeerServicePlugin(private val context: Context, messenger: BinaryMessenger) {

    private val main = Handler(Looper.getMainLooper())
    private val client: ConnectionsClient = Nearby.getConnectionsClient(context)

    private val control = MethodChannel(messenger, "noti.peer/control")
    private val peersSink = SinkHandler().also {
        EventChannel(messenger, "noti.peer/peers").setStreamHandler(it)
    }
    private val invitesSink = SinkHandler().also {
        EventChannel(messenger, "noti.peer/invites").setStreamHandler(it)
    }
    private val payloadsSink = SinkHandler().also {
        EventChannel(messenger, "noti.peer/payloads").setStreamHandler(it)
    }
    private val transfersSink = SinkHandler().also {
        EventChannel(messenger, "noti.peer/transfers").setStreamHandler(it)
    }

    private var serviceType: String = "noti-share"
    private var displayName: String = "noti"
    private var advertising = false
    private var discovering = false

    /** endpointId -> friendly display name reported by remote */
    private val peerNames = ConcurrentHashMap<String, String>()

    /** endpointId -> "found" | "inviting" | "accepting" | "connected" | "disconnected" */
    private val peerStates = ConcurrentHashMap<String, String>()

    /** inviteId -> endpointId */
    private val pendingInvites = ConcurrentHashMap<String, String>()

    /** payloadId (long, as String) -> transferId (uuid) */
    private val transferIdsByPayload = ConcurrentHashMap<Long, String>()
    private val totalsByPayload = ConcurrentHashMap<Long, Long>()
    private val payloadEndpoint = ConcurrentHashMap<Long, String>()
    private val payloadDirection = ConcurrentHashMap<Long, String>()

    init {
        control.setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "start" -> start(call, result)
                "stop" -> stop(result)
                "invite" -> invite(call, result)
                "acceptInvite" -> acceptInvite(call, result)
                "rejectInvite" -> rejectInvite(call, result)
                "sendBytes" -> sendBytes(call, result)
                "sendFile" -> sendFile(call, result)
                "cancelTransfer" -> cancelTransfer(call, result)
                "disconnect" -> disconnect(call, result)
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            result.error("native_error", t.message, null)
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val role = call.argument<String>("role") ?: "both"
        displayName = call.argument<String>("displayName") ?: "noti"
        serviceType = call.argument<String>("serviceType") ?: "noti-share"

        if (role == "advertise" || role == "both") {
            client.startAdvertising(
                displayName,
                serviceType,
                connectionLifecycle,
                AdvertisingOptions.Builder().setStrategy(Strategy.P2P_CLUSTER).build()
            )
            advertising = true
        }
        if (role == "discover" || role == "both") {
            client.startDiscovery(
                serviceType,
                endpointDiscovery,
                DiscoveryOptions.Builder().setStrategy(Strategy.P2P_CLUSTER).build()
            )
            discovering = true
        }
        emitPeers()
        result.success(null)
    }

    private fun stop(result: MethodChannel.Result) {
        if (advertising) client.stopAdvertising()
        if (discovering) client.stopDiscovery()
        client.stopAllEndpoints()
        advertising = false
        discovering = false
        peerNames.clear()
        peerStates.clear()
        pendingInvites.clear()
        transferIdsByPayload.clear()
        totalsByPayload.clear()
        payloadEndpoint.clear()
        payloadDirection.clear()
        peersSink.send(emptyList<Map<String, Any>>())
        result.success(null)
    }

    private fun invite(call: MethodCall, result: MethodChannel.Result) {
        val peerId = call.argument<String>("peerId")
            ?: return result.error("bad_args", "peerId missing", null)
        peerStates[peerId] = "inviting"
        emitPeers()
        client.requestConnection(displayName, peerId, connectionLifecycle)
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { e -> result.error("invite_failed", e.message, null) }
    }

    private fun acceptInvite(call: MethodCall, result: MethodChannel.Result) {
        val inviteId = call.argument<String>("inviteId")
            ?: return result.error("bad_args", "inviteId missing", null)
        val endpointId = pendingInvites.remove(inviteId)
            ?: return result.error("no_invite", "Unknown invite id", null)
        peerStates[endpointId] = "accepting"
        emitPeers()
        client.acceptConnection(endpointId, payloadCallback)
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { e -> result.error("accept_failed", e.message, null) }
    }

    private fun rejectInvite(call: MethodCall, result: MethodChannel.Result) {
        val inviteId = call.argument<String>("inviteId")
            ?: return result.error("bad_args", "inviteId missing", null)
        val endpointId = pendingInvites.remove(inviteId)
            ?: return result.error("no_invite", "Unknown invite id", null)
        client.rejectConnection(endpointId)
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { e -> result.error("reject_failed", e.message, null) }
    }

    private fun sendBytes(call: MethodCall, result: MethodChannel.Result) {
        val peerId = call.argument<String>("peerId")
            ?: return result.error("bad_args", "peerId missing", null)
        val bytes = call.argument<ByteArray>("bytes")
            ?: return result.error("bad_args", "bytes missing", null)
        val transferId = UUID.randomUUID().toString()
        val payload = Payload.fromBytes(bytes)
        registerOutgoing(payload.id, transferId, peerId, bytes.size.toLong())
        client.sendPayload(peerId, payload)
            .addOnSuccessListener { result.success(transferId) }
            .addOnFailureListener { e -> result.error("send_failed", e.message, null) }
    }

    private fun sendFile(call: MethodCall, result: MethodChannel.Result) {
        val peerId = call.argument<String>("peerId")
            ?: return result.error("bad_args", "peerId missing", null)
        val path = call.argument<String>("path")
            ?: return result.error("bad_args", "path missing", null)
        val maxBytes = (call.argument<Int>("maxBytes") ?: Int.MAX_VALUE).toLong()
        val file = File(path)
        if (!file.exists()) return result.error("no_file", "File not found", null)
        if (file.length() > maxBytes) return result.error("too_large", "File exceeds cap", null)
        val pfd = context.contentResolver.openFileDescriptor(android.net.Uri.fromFile(file), "r")
            ?: return result.error("no_file", "Cannot open file", null)
        val transferId = UUID.randomUUID().toString()
        val payload = Payload.fromFile(pfd)
        registerOutgoing(payload.id, transferId, peerId, file.length())
        client.sendPayload(peerId, payload)
            .addOnSuccessListener {
                // Nearby copies the FD before sendPayload returns; close ours
                // to avoid leaking a descriptor per file send.
                try { pfd.close() } catch (_: Throwable) {}
                result.success(transferId)
            }
            .addOnFailureListener { e ->
                try { pfd.close() } catch (_: Throwable) {}
                result.error("send_failed", e.message, null)
            }
    }

    private fun cancelTransfer(call: MethodCall, result: MethodChannel.Result) {
        val transferId = call.argument<String>("transferId")
            ?: return result.error("bad_args", "transferId missing", null)
        val payloadId = transferIdsByPayload.entries.firstOrNull { it.value == transferId }?.key
            ?: return result.success(null)
        client.cancelPayload(payloadId)
        result.success(null)
    }

    private fun disconnect(call: MethodCall, result: MethodChannel.Result) {
        val peerId = call.argument<String>("peerId")
            ?: return result.error("bad_args", "peerId missing", null)
        client.disconnectFromEndpoint(peerId)
        peerStates[peerId] = "disconnected"
        emitPeers()
        result.success(null)
    }

    private fun registerOutgoing(payloadId: Long, transferId: String, peerId: String, total: Long) {
        transferIdsByPayload[payloadId] = transferId
        totalsByPayload[payloadId] = total
        payloadEndpoint[payloadId] = peerId
        payloadDirection[payloadId] = "send"
        emitTransfer(transferId, peerId, "send", "queued", 0, total)
    }

    private fun emitPeers() {
        val list = peerNames.map { (id, name) ->
            mapOf(
                "id" to id,
                "displayName" to name,
                "state" to (peerStates[id] ?: "found")
            )
        }
        peersSink.send(list)
    }

    private fun emitTransfer(
        transferId: String,
        peerId: String,
        direction: String,
        phase: String,
        bytes: Long,
        total: Long,
        error: String? = null,
    ) {
        val ev = mutableMapOf<String, Any>(
            "transferId" to transferId,
            "peerId" to peerId,
            "direction" to direction,
            "phase" to phase,
            "bytes" to bytes.toInt(),
            "total" to total.toInt(),
        )
        if (error != null) ev["error"] = error
        transfersSink.send(ev)
    }

    private val endpointDiscovery = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            peerNames[endpointId] = info.endpointName
            peerStates[endpointId] = "found"
            emitPeers()
        }

        override fun onEndpointLost(endpointId: String) {
            peerNames.remove(endpointId)
            peerStates.remove(endpointId)
            emitPeers()
        }
    }

    private val connectionLifecycle = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            peerNames[endpointId] = info.endpointName
            // If we initiated, we already accept implicitly; otherwise emit invite.
            if (peerStates[endpointId] == "inviting") {
                client.acceptConnection(endpointId, payloadCallback)
            } else {
                val inviteId = UUID.randomUUID().toString()
                pendingInvites[inviteId] = endpointId
                invitesSink.send(
                    mapOf(
                        "id" to inviteId,
                        "peerId" to endpointId,
                        "peerName" to info.endpointName,
                    )
                )
            }
        }

        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            peerStates[endpointId] = if (result.status.isSuccess) "connected" else "disconnected"
            emitPeers()
        }

        override fun onDisconnected(endpointId: String) {
            peerStates[endpointId] = "disconnected"
            emitPeers()
        }
    }

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            val transferId = transferIdsByPayload.getOrPut(payload.id) { UUID.randomUUID().toString() }
            payloadEndpoint[payload.id] = endpointId
            payloadDirection[payload.id] = "receive"
            when (payload.type) {
                Payload.Type.BYTES -> {
                    val bytes = payload.asBytes() ?: ByteArray(0)
                    payloadsSink.send(
                        mapOf(
                            "peerId" to endpointId,
                            "bytes" to bytes,
                        )
                    )
                    emitTransfer(transferId, endpointId, "receive", "completed", bytes.size.toLong(), bytes.size.toLong())
                }
                Payload.Type.FILE -> {
                    val uri = payload.asFile()?.asUri()
                    val path = uri?.path
                    if (path != null) {
                        payloadsSink.send(
                            mapOf(
                                "peerId" to endpointId,
                                "bytes" to ByteArray(0),
                                "filePath" to path,
                            )
                        )
                    }
                }
                else -> Unit
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {
            val transferId = transferIdsByPayload[update.payloadId] ?: return
            val total = totalsByPayload[update.payloadId] ?: update.totalBytes
            val direction = payloadDirection[update.payloadId] ?: "receive"
            val phase = when (update.status) {
                PayloadTransferUpdate.Status.IN_PROGRESS -> "inProgress"
                PayloadTransferUpdate.Status.SUCCESS -> "completed"
                PayloadTransferUpdate.Status.CANCELED -> "cancelled"
                PayloadTransferUpdate.Status.FAILURE -> "failed"
                else -> "inProgress"
            }
            emitTransfer(transferId, endpointId, direction, phase, update.bytesTransferred, total)
            if (phase != "inProgress") {
                transferIdsByPayload.remove(update.payloadId)
                totalsByPayload.remove(update.payloadId)
                payloadEndpoint.remove(update.payloadId)
                payloadDirection.remove(update.payloadId)
            }
        }
    }

    inner class SinkHandler : EventChannel.StreamHandler {
        private var sink: EventChannel.EventSink? = null
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            sink = events
        }
        override fun onCancel(arguments: Any?) {
            sink = null
        }
        fun send(value: Any) {
            main.post { sink?.success(value) }
        }
    }
}
