package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.ProtocolVersion

class ViewerHandshakeResult(val sessionId: String, val caps: Long, val ready: ControlMessage.DisplayReady)

/** Viewer: hello → welcome → display.config → display.ready (spec control-messages.md). */
object ViewerHandshake {
    const val STEP_TIMEOUT_MS = 10_000

    fun run(conn: ControlConnection, name: String, caps: Long, display: ControlMessage.DisplayConfig): ViewerHandshakeResult {
        conn.setReadTimeout(STEP_TIMEOUT_MS)
        val helloId = conn.send(ControlMessage.Hello(ProtocolVersion.CURRENT.string, caps, name))
        val welcome = expect<ControlMessage.Welcome>(conn, helloId)
        val configId = conn.send(display)
        val ready = expect<ControlMessage.DisplayReady>(conn, configId)
        conn.setReadTimeout(0)
        return ViewerHandshakeResult(welcome.sessionId, welcome.caps and caps, ready)
    }

    /** Đọc đến message có đúng `id` và kiểu mong đợi. `reject` → lỗi có lý do; message khác → vi phạm giao thức. */
    private inline fun <reified T : ControlMessage> expect(conn: ControlConnection, id: Long): T {
        val inbound = conn.nextInbound() ?: transportError(TransportErrorCode.CONNECTION_CLOSED)
        val envelope = (inbound as? ControlInbound.Message)?.envelope
        if (envelope == null) {
            conn.close()
            transportError(TransportErrorCode.PROTOCOL_VIOLATION, "cần message điều khiển")
        }
        val message = envelope.message
        if (message is ControlMessage.Reject) {
            conn.close()
            throw TransportException(TransportErrorCode.REJECTED, message.detail, message.reason)
        }
        if (envelope.id != id || message !is T) {
            conn.close()
            transportError(TransportErrorCode.PROTOCOL_VIOLATION, "không mong đợi ${message::class.simpleName}")
        }
        return message
    }
}
