package vn.xox.xdesk.app.input

import vn.xox.xdesk.transport.InputEvents
import vn.xox.xdesk.wire.InputEvent

/**
 * Lặp phím phía viewer (host không tự lặp): giữ phím không phải bổ trợ quá [delayMs] thì phát lại `key down`
 * mỗi [intervalMs] như macOS. Chỉ phím nhấn gần nhất được lặp.
 */
class KeyRepeater(private val delayMs: Long = DEFAULT_DELAY_MS, intervalMs: Long = DEFAULT_INTERVAL_MS) {
    private val intervalMs = maxOf(1L, intervalMs)
    private var held: Held? = null

    private class Held(val usage: Int, val mods: Int, var nextFireMs: Long)

    val isRepeating: Boolean get() = held != null

    fun keyDown(usage: Int, mods: Int, nowMs: Long) {
        if (MacKeyLayout.isModifier(usage)) return
        held = Held(usage, mods, nowMs + delayMs)
    }

    fun keyUp(usage: Int) {
        if (held?.usage == usage) held = null
    }

    fun releaseAll() { held = null }

    /** Gọi định kỳ; trả các `key down` đã đến hạn (tối đa [MAX_BURST] mỗi lần để không dồn cục). */
    fun tick(nowMs: Long): List<InputEvent> {
        val key = held ?: return emptyList()
        if (nowMs < key.nextFireMs) return emptyList()
        val due = minOf(MAX_BURST, (nowMs - key.nextFireMs) / intervalMs + 1).toInt()
        key.nextFireMs = nowMs + intervalMs
        return List(due) { InputEvents.key(key.usage, true, key.mods) }
    }

    companion object {
        const val DEFAULT_DELAY_MS = 400L
        const val DEFAULT_INTERVAL_MS = 33L
        const val MAX_BURST = 4L
    }
}
