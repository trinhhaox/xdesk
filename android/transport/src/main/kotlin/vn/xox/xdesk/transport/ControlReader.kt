package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.ControlMessage

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
) {
    fun run() {
        try {
            while (true) {
                val inbound = conn.nextInbound() ?: break
                when (val message = (inbound as? ControlInbound.Message)?.envelope?.message) {
                    is ControlMessage.Pong -> onPong(message)
                    is ControlMessage.RekeyResync -> onResync(message)
                    is ControlMessage.AgentApprove -> onAgentApprove(message)
                    is ControlMessage.AgentHelp -> onAgentHelp(message)
                    is ControlMessage.Bye -> return onEnd("Host đã ngắt: ${message.reason.orEmpty()}", null)
                    is ControlMessage.Reject -> return rejected(message)
                    else -> Unit
                }
            }
            onEnd("Host đã ngắt kết nối", null)
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
