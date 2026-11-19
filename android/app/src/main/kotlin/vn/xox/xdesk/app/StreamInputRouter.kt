package vn.xox.xdesk.app

import android.os.SystemClock
import vn.xox.xdesk.app.input.GestureConfig
import vn.xox.xdesk.app.input.GestureInterpreter
import vn.xox.xdesk.app.input.TextAction
import vn.xox.xdesk.app.input.TextInputBridge
import vn.xox.xdesk.app.input.TouchSample
import vn.xox.xdesk.app.input.HidKeys
import vn.xox.xdesk.transport.InputEvents
import vn.xox.xdesk.transport.ViewerSession

/** Đưa cảm ứng, bàn phím ảo/cứng và phím đặc biệt tới host. Gọi từ main thread; việc gửi mạng do [ViewerSession] đẩy sang thread I/O. */
class StreamInputRouter(private val session: ViewerSession) {
    private var gestures: GestureInterpreter? = null
    private val text = TextInputBridge()

    /** Đổi kích thước host (điểm) mỗi khi `display.config` đổi: ngưỡng và delta cuộn tính theo điểm host. */
    fun configure(hostWidthPoints: Float, hostHeightPoints: Float) {
        gestures = GestureInterpreter(GestureConfig(hostWidthPoints, hostHeightPoints))
    }

    fun onTouch(samples: List<TouchSample>) {
        val interpreter = gestures ?: return
        session.sendInput(samples.flatMap(interpreter::handle))
    }

    /** Gọi ~50 ms/lần để phát click phải khi giữ lâu. */
    fun tick() {
        gestures?.tick(SystemClock.uptimeMillis())?.takeIf { it.isNotEmpty() }?.let(session::sendInput)
    }

    fun commitText(value: String) = apply(text.commit(value))
    fun setComposing(value: String) = apply(text.setComposing(value))
    fun finishComposing() = apply(text.finishComposing())
    fun deleteBefore(count: Int) = apply(text.deleteBefore(count))

    fun tapKey(usage: Int, mods: Int = 0) {
        session.sendInput(listOf(InputEvents.key(usage, true, mods), InputEvents.key(usage, false, mods)))
    }

    private fun apply(actions: List<TextAction>) {
        for (action in actions) when (action) {
            is TextAction.Insert -> session.sendText(action.text)
            is TextAction.Backspaces -> repeat(action.count) { tapKey(HidKeys.BACKSPACE) }
        }
    }
}
