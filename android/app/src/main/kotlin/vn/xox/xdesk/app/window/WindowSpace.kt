package vn.xox.xdesk.app.window

import vn.xox.xdesk.app.input.VideoContentMapper
import vn.xox.xdesk.app.input.VideoViewport
import vn.xox.xdesk.wire.WindowFrame

/** Hình chữ nhật trong toạ độ view (px). */
data class ViewRect(val left: Float, val top: Float, val right: Float, val bottom: Float) {
    val width: Float get() = right - left
    val height: Float get() = bottom - top
    fun contains(x: Float, y: Float): Boolean = x in left..right && y in top..bottom
}

/**
 * Đổi qua lại giữa toạ độ view (px) và toạ độ điểm của luồng video (kích thước khung giải mã ÷ `display.config.scale`),
 * cùng phép ánh xạ với chạm trực tiếp: letterbox ([VideoContentMapper]), zoom/kéo ([VideoViewport]) và độ dịch lên của bàn phím [panY].
 */
class WindowSpace(
    private val mapper: VideoContentMapper,
    private val viewport: VideoViewport,
    private val panY: Float,
    val pointsWidth: Double,
    val pointsHeight: Double,
) {
    /** Điểm chạm (view) → điểm video; null khi chạm vào dải đen ngoài khung video. */
    fun viewToPoint(x: Float, y: Float): Pair<Double, Double>? {
        val (bx, by) = viewport.toBase(x, y + panY, mapper)
        val (nx, ny) = mapper.normalize(bx, by) ?: return null
        return nx * pointsWidth to ny * pointsHeight
    }

    fun pointToView(px: Double, py: Double): Pair<Float, Float> {
        val bx = mapper.originX + (px / pointsWidth).toFloat() * mapper.width
        val by = mapper.originY + (py / pointsHeight).toFloat() * mapper.height
        val (vx, vy) = viewport.toView(bx, by, mapper)
        return vx to (vy - panY)
    }

    /** Độ dời ngón (px) → độ dời trong điểm video. */
    fun deltaToPoints(dx: Float, dy: Float): Pair<Double, Double> =
        dx * pointsWidth / (mapper.width * viewport.zoom) to dy * pointsHeight / (mapper.height * viewport.zoom)

    fun frameToView(frame: WindowFrame): ViewRect {
        val (l, t) = pointToView(frame.x, frame.y)
        val (r, b) = pointToView(frame.x + frame.w, frame.y + frame.h)
        return ViewRect(l, t, r, b)
    }

    companion object {
        /** null khi cỡ view, video hoặc scale không hợp lệ. */
        fun of(mapper: VideoContentMapper?, viewport: VideoViewport, panY: Float, points: Pair<Double, Double>?): WindowSpace? {
            val (w, h) = points ?: return null
            if (mapper == null || !(w.isFinite() && h.isFinite() && w > 0.0 && h > 0.0)) return null
            return WindowSpace(mapper, viewport, panY, w, h)
        }
    }
}
