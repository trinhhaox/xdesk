package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.InputEvent
import vn.xox.xdesk.wire.InputKind

/**
 * Phía gửi của kênh input: cấp seq (đơn điệu từ 1; 0 = không tin cậy) cho down/up/key, giữ tới khi nhận input-ack,
 * gửi lại mỗi [RESEND_INTERVAL_MS] tối đa [MAX_RESENDS] lần rồi bỏ. Thời gian do người gọi truyền để test xác định. Không thread-safe.
 */
class InputSequencer {
    private class Pending(val event: InputEvent, var lastSentMs: Long, var resends: Int = 0)

    class DueResult(val resend: List<InputEvent>, val abandoned: List<InputEvent>)

    private var nextSeq = 1L
    private val pending = ArrayList<Pending>()
    private val heldButtons = HashSet<Int>()
    private val heldKeys = HashSet<Int>()

    val pendingCount: Int get() = pending.size

    /** Còn nút/phím đang giữ → người gọi nên gửi [InputEvents.heartbeat] định kỳ. */
    val hasHeldInput: Boolean get() = heldButtons.isNotEmpty() || heldKeys.isNotEmpty()

    fun prepare(events: List<InputEvent>, nowMs: Long): List<InputEvent> = events.map { original ->
        if (!original.isReliable) return@map original
        val event = original.copy(seq = nextSeq)
        nextSeq = (nextSeq + 1) and 0xFFFFFFFFL
        track(event)
        pending += Pending(event, nowMs)
        event
    }

    /** Host đã nhận liên tục tới `seq`. */
    fun acknowledge(seq: Long) {
        pending.removeAll { it.event.seq <= seq }
    }

    fun resendDue(nowMs: Long): DueResult {
        val resend = ArrayList<InputEvent>()
        val abandoned = ArrayList<InputEvent>()
        val iterator = pending.iterator()
        while (iterator.hasNext()) {
            val item = iterator.next()
            if (nowMs - item.lastSentMs < RESEND_INTERVAL_MS) continue
            if (item.resends >= MAX_RESENDS) {
                abandoned += item.event
                iterator.remove()
            } else {
                item.resends++
                item.lastSentMs = nowMs
                resend += item.event
            }
        }
        return DueResult(resend, abandoned)
    }

    private fun track(event: InputEvent) {
        when (event.kind) {
            InputKind.DOWN -> heldButtons += event.button
            InputKind.UP -> heldButtons -= event.button
            InputKind.KEY -> if (event.button == 1) heldKeys += event.keyUsage else heldKeys -= event.keyUsage
            else -> Unit
        }
    }

    companion object {
        const val RESEND_INTERVAL_MS = 100L
        const val MAX_RESENDS = 3

        /** Chia thành các lô ≤ [InputEvent.MAX_BATCH] sự kiện, giữ nguyên thứ tự. */
        fun batches(events: List<InputEvent>): List<List<InputEvent>> = events.chunked(InputEvent.MAX_BATCH)
    }
}
