package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.MediaPacket

internal fun describeError(e: Exception): String = when (e) {
    is TransportException -> e.message.orEmpty()
    else -> "Lỗi giao thức: ${e::class.simpleName}"
}

/**
 * Vòng đọc kênh điều khiển của phiên (chạy trên thread riêng, tới khi kênh đóng). Kết thúc luôn gọi [onEnd] đúng một lần.
 * `reject{revoked}` (đã xác thực trên kênh mã hoá) → [onRevoked] để quên host, rồi kết thúc.
 */
internal class ControlReader(
    private val conn: ControlConnection,
    private val onPong: (ControlMessage.Pong) -> Unit,
    private val onResync: (ControlMessage.RekeyResync) -> Unit,
    private val onAgentApprove: (ControlMessage.AgentApprove) -> Unit,
    private val onAgentHelp: (ControlMessage.AgentHelp) -> Unit = {},
    private val onRevoked: () -> Unit,
    private val onEnd: (String, TransportErrorCode?) -> Unit,
    private val onDisplayReady: (Long, ControlMessage.DisplayReady) -> Unit = { _, _ -> },
    private val onMediaOverTcp: (MediaPacket) -> Unit = {},
    private val onBulk: (ByteArray) -> Unit = {},
    private val onClipboard: (ControlMessage) -> Unit = {},
    private val onFileTransfer: (ControlMessage) -> Unit = {},
    private val onDisplayList: (ControlMessage.DisplayList) -> Unit = {},
    private val onUnlockResult: (ControlMessage.SystemUnlockResult) -> Unit = {},
) {
    fun run() {
        try {
            while (true) {
                val inbound = conn.nextInbound() ?: break
                val envelope = when (inbound) {
                    is ControlInbound.MediaOverTcp -> {
                        onMediaOverTcp(inbound.packet)
                        continue
                    }
                    is ControlInbound.Bulk -> {
                        onBulk(inbound.bytes)
                        continue
                    }
                    is ControlInbound.Message -> inbound.envelope
                }
                when (val message = envelope.message) {
                    is ControlMessage.DisplayReady -> onDisplayReady(envelope.id, message)
                    is ControlMessage.DisplayList -> onDisplayList(message)
                    is ControlMessage.SystemUnlockResult -> onUnlockResult(message)
                    is ControlMessage.ClipOffer, is ControlMessage.ClipPull, is ControlMessage.ClipData -> onClipboard(message)
                    is ControlMessage.FileStart, is ControlMessage.FileChunk, is ControlMessage.FileDone, is ControlMessage.FileCancel ->
                        onFileTransfer(message)
                    is ControlMessage.Pong -> onPong(message)
                    is ControlMessage.RekeyResync -> onResync(message)
                    is ControlMessage.AgentApprove -> onAgentApprove(message)
                    is ControlMessage.AgentHelp -> onAgentHelp(message)
                    is ControlMessage.Bye -> return onEnd("Host đã ngắt: ${message.reason.orEmpty()}", TransportErrorCode.REJECTED)
                    is ControlMessage.Reject -> return rejected(message)
                    else -> Unit
                }
            }
            onEnd("Host đã ngắt kết nối", TransportErrorCode.CONNECTION_CLOSED)
        } catch (e: Exception) {
            onEnd(describeError(e), (e as? TransportException)?.code)
        }
    }

    private fun rejected(message: ControlMessage.Reject) {
        if (message.reason == ControlMessage.Reject.REASON_REVOKED) {
            onRevoked()
            onEnd(TransportErrorCode.REVOKED_BY_HOST.message, TransportErrorCode.REVOKED_BY_HOST)
        } else {
            onEnd("Host từ chối: ${message.reason}", TransportErrorCode.REJECTED)
        }
    }
}
