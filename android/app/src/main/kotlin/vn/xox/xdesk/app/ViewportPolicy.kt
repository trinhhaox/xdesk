package vn.xox.xdesk.app

import kotlin.math.abs

/** Khi nào phiên đang chạy phải xin lại `display.config` vì vùng hiển thị thật khác vùng đã xin (xoay máy, vùng an toàn đổi). */
object ViewportPolicy {
    const val ASPECT_TOLERANCE = 0.015f

    /**
     * `native` (Giống màn hình Mac) không bao giờ đàm phán lại: Mac giữ nguyên, xoay máy chỉ đổi khung letterbox.
     * Còn lại: đổi chiều ngang/dọc, hoặc tỉ lệ lệch quá [ASPECT_TOLERANCE], thì video đang bị kéo giãn nên phải xin lại đúng cỡ vùng thật.
     */
    fun needsRenegotiation(native: Boolean, requested: Pair<Int, Int>, actual: Pair<Int, Int>): Boolean {
        if (native) return false
        val (rw, rh) = requested
        val (aw, ah) = actual
        if (rw <= 0 || rh <= 0 || aw <= 0 || ah <= 0) return false
        if ((rw > rh) != (aw > ah)) return true
        val requestedAspect = rw.toFloat() / rh
        return abs(aw.toFloat() / ah - requestedAspect) / requestedAspect > ASPECT_TOLERANCE
    }
}
