package vn.xox.xdesk.app.input

import kotlin.math.exp
import kotlin.math.hypot

/**
 * Cuộn quán tính (giống iOS `ScrollMomentum`): hất ngón rồi nhả thì trang trôi tiếp và chậm dần.
 * Đo vận tốc từ các lần cuộn gần nhất; sau khi nhả, mỗi [step] phát thêm một đoạn cuộn tới khi đủ chậm.
 */
internal class ScrollMomentum {
    private var vx = 0f
    private var vy = 0f
    private var lastScrollMs: Long? = null
    private var lastStepMs = 0L
    var isActive = false
        private set

    /** Ghi nhận một lần cuộn do ngón tay (điểm host) để ước lượng vận tốc (điểm/giây), làm mượt theo trung bình trượt. */
    fun track(dx: Float, dy: Float, timeMs: Long) {
        val last = lastScrollMs
        lastScrollMs = timeMs
        if (last == null || timeMs <= last) return
        val dt = (timeMs - last) / 1000f
        vx = BLEND * (dx / dt) + (1 - BLEND) * vx
        vy = BLEND * (dy / dt) + (1 - BLEND) * vy
    }

    /** Ngón vừa nhả: còn đủ nhanh thì bắt đầu trôi. Trả `true` nếu đang trôi. */
    fun release(timeMs: Long): Boolean {
        val last = lastScrollMs
        lastScrollMs = null
        if (last == null || timeMs - last > RELEASE_WINDOW_MS) return stop()
        val speed = hypot(vx, vy)
        if (speed < MIN_SPEED) return stop()
        if (speed > MAX_SPEED) { vx *= MAX_SPEED / speed; vy *= MAX_SPEED / speed }
        lastStepMs = timeMs
        isActive = true
        return true
    }

    /** Đoạn cuộn kế tiếp tới [nowMs]; null khi đã dừng. */
    fun step(nowMs: Long): Pair<Float, Float>? {
        if (!isActive || nowMs <= lastStepMs) return null
        val dt = (nowMs - lastStepMs).toFloat()
        lastStepMs = nowMs
        val decay = exp(-dt / DECAY_MS)
        // Quãng đi được trong dt khi vận tốc giảm theo hàm mũ.
        val factor = DECAY_MS / 1000f * (1 - decay)
        val delta = vx * factor to vy * factor
        vx *= decay; vy *= decay
        if (hypot(vx, vy) < MIN_SPEED) stop()
        return delta
    }

    /** Dừng trôi (ngón chạm lại màn hình, đổi cử chỉ). */
    fun stop(): Boolean {
        isActive = false
        vx = 0f; vy = 0f
        lastScrollMs = null
        return false
    }

    private companion object {
        /** Nhả ngón quá lâu sau lần cuộn cuối (ngón đã dừng) thì không trôi. */
        const val RELEASE_WINDOW_MS = 80L
        /** Thời hằng giảm tốc (ms): vận tốc còn ~37% sau mỗi khoảng này. */
        const val DECAY_MS = 325f
        /** Dưới tốc độ này (điểm host/giây) thì không bắt đầu hoặc dừng trôi. */
        const val MIN_SPEED = 60f
        /** Chặn tốc độ để một cú hất mạnh không văng quá xa. */
        const val MAX_SPEED = 12_000f
        const val BLEND = 0.6f
    }
}
