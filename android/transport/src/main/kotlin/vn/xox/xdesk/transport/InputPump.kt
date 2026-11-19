package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.InputAck
import vn.xox.xdesk.wire.InputEvent
import vn.xox.xdesk.wire.MediaPacket
import vn.xox.xdesk.wire.MediaPacketType

/**
 * Gửi input tới host qua UDP: cấp seq và gửi lại tới khi host ack; khi còn nút/phím giữ thì gửi heartbeat.
 * Không thread-safe: mọi lời gọi phải cùng một thread (executor I/O của phiên).
 */
internal class InputPump(private val streamId: Int, private val send: (MediaPacket) -> Unit, private val onError: (String) -> Unit) {
    private val sequencer = InputSequencer()
    private var lastHeartbeatMs = 0L

    /** Số sự kiện tin cậy đang chờ ack (đọc từ thread khác chỉ để hiển thị/kiểm thử). */
    val pendingCount: Int get() = sequencer.pendingCount

    fun submit(events: List<InputEvent>, nowMs: Long) {
        val valid = events.mapNotNull(InputEvents::sanitized)
        if (valid.isNotEmpty()) transmit(sequencer.prepare(valid, nowMs))
    }

    /** Gọi định kỳ (~50 ms): gửi lại sự kiện chưa ack và heartbeat. */
    fun maintain(nowMs: Long) {
        val due = sequencer.resendDue(nowMs)
        if (due.abandoned.isNotEmpty()) onError("input bị bỏ vì host không ack: ${due.abandoned.size}")
        val outgoing = due.resend.toMutableList()
        if (sequencer.hasHeldInput && nowMs - lastHeartbeatMs >= HEARTBEAT_INTERVAL_MS) {
            outgoing += InputEvents.heartbeat
            lastHeartbeatMs = nowMs
        }
        if (outgoing.isNotEmpty()) transmit(outgoing)
    }

    fun handleAck(packet: MediaPacket) {
        if (packet.header.type != MediaPacketType.INPUT_ACK) return
        try {
            sequencer.acknowledge(InputAck.decode(packet.payload).seq)
        } catch (e: vn.xox.xdesk.wire.WireException) {
            onError("input-ack sai định dạng")
        }
    }

    private fun transmit(events: List<InputEvent>) {
        for (batch in InputSequencer.batches(events)) {
            try {
                send(MediaPacket.input(streamId, batch))
            } catch (e: TransportException) {
                onError(e.message.orEmpty())
            }
        }
    }

    companion object {
        const val MAINTENANCE_INTERVAL_MS = 50L
        const val HEARTBEAT_INTERVAL_MS = 250L
    }
}
