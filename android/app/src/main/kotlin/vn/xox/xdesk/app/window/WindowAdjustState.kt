package vn.xox.xdesk.app.window

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.WindowFrame
import vn.xox.xdesk.wire.WindowPreset

/**
 * Trạng thái chế độ "Chỉnh cửa sổ" (chỉ main thread). Khung hiển thị [frame] là khung dự đoán phía viewer: bám tay ngay, còn lệnh gửi host
 * được gộp và nhả tối đa mỗi [MIN_SEND_INTERVAL_NANOS] bởi [flush] (gọi mỗi khung hình). Khung do host trả về chỉ được nhận khi không còn
 * ngón nào đang chỉnh, không còn lệnh chờ gửi và không còn phản hồi nào đang bay, để khung không giật lùi giữa chừng.
 */
class WindowAdjustState(
    private val pick: (Double, Double) -> Unit,
    private val adjust: (ControlMessage.WindowAdjust) -> Unit,
    private val toast: (String) -> Unit,
) {
    var active by mutableStateOf(false)
        private set
    var selection by mutableStateOf<ControlMessage.WindowSelected?>(null)
        private set
    var frame by mutableStateOf<WindowFrame?>(null)
        private set

    val canAdjust: Boolean get() = selection?.windowId != null && frame != null
    val canResize: Boolean get() = canAdjust && selection?.resizable != false

    private var gestureActive = false
    private var pendingDx = 0.0
    private var pendingDy = 0.0
    private var pendingSize: Pair<Double, Double>? = null
    private var lastSentResize = false
    private var lastFlushNanos: Long? = null
    private var inFlight = 0

    fun enter() { active = true }

    fun exit() {
        active = false
        selection = null
        frame = null
        resetPending()
    }

    fun requestPick(x: Double, y: Double) {
        inFlight = 0
        pick(x, y)
    }

    fun beginGesture() { gestureActive = true }

    fun endGesture() { gestureActive = false }

    /** Phản hồi `window.selected` của host (đã đẩy sang main thread). */
    fun onSelected(msg: ControlMessage.WindowSelected) {
        if (!active) return
        if (inFlight > 0) inFlight--
        if (!msg.ok || msg.windowId == null || msg.frame == null) {
            toast(msg.message ?: "Không chỉnh được cửa sổ này")
            return
        }
        val sameWindow = selection?.windowId == msg.windowId
        selection = msg
        if (!sameWindow || (!gestureActive && !hasPending && inFlight == 0)) {
            if (!sameWindow) resetPending()
            frame = msg.frame
        }
    }

    /** Khung mới do cử chỉ tính ra: cập nhật khung dự đoán và cộng dồn phần dời tâm + kích thước cần gửi. */
    fun update(next: WindowFrame) {
        val current = frame ?: return
        if (next == current) return
        pendingDx += (next.x + next.w / 2) - (current.x + current.w / 2)
        pendingDy += (next.y + next.h / 2) - (current.y + current.h / 2)
        if (next.w != current.w || next.h != current.h) pendingSize = next.w to next.h
        frame = next
    }

    fun applyPreset(preset: WindowPreset) {
        val id = selection?.windowId ?: return
        resetPending()
        send(ControlMessage.WindowAdjust.preset(id, preset))
    }

    /** Gửi tối đa một lệnh mỗi lần gọi và không quá 60 lệnh/giây; resize và move luân phiên khi cùng chờ. */
    fun flush(nowNanos: Long) {
        if (!hasPending || lastFlushNanos?.let { nowNanos - it < MIN_SEND_INTERVAL_NANOS } == true) return
        val id = selection?.windowId ?: return resetPending()
        val size = pendingSize
        val hasMove = pendingDx != 0.0 || pendingDy != 0.0
        lastFlushNanos = nowNanos
        if (size != null && !(hasMove && lastSentResize)) {
            pendingSize = null
            lastSentResize = true
            send(ControlMessage.WindowAdjust.resize(id, size.first, size.second))
        } else {
            val dx = pendingDx
            val dy = pendingDy
            pendingDx = 0.0
            pendingDy = 0.0
            lastSentResize = false
            send(ControlMessage.WindowAdjust.move(id, dx, dy))
        }
    }

    private val hasPending: Boolean get() = pendingSize != null || pendingDx != 0.0 || pendingDy != 0.0

    private fun send(message: ControlMessage.WindowAdjust) {
        inFlight++
        adjust(message)
    }

    private fun resetPending() {
        pendingDx = 0.0
        pendingDy = 0.0
        pendingSize = null
        inFlight = 0
    }

    companion object {
        const val MIN_SEND_INTERVAL_NANOS = 16_000_000L
    }
}
