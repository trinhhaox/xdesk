package vn.xox.xdesk.app.window

import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import vn.xox.xdesk.wire.WindowFrame

enum class Corner { TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

/** Cử chỉ → khung cửa sổ mới, thuần toán trong toạ độ điểm video; giới hạn kích thước giống host (tối thiểu 200×150, tối đa cả màn). */
object WindowFrameOps {
    const val MIN_WIDTH = 200.0
    const val MIN_HEIGHT = 150.0

    fun translate(frame: WindowFrame, dx: Double, dy: Double): WindowFrame = frame.copy(x = frame.x + dx, y = frame.y + dy)

    /** Chụm/mở theo tỉ lệ [scale] quanh tâm, giữ tỉ lệ khung; không nhỏ hơn mức tối thiểu, không lớn hơn màn ([maxW] × [maxH]). */
    fun pinch(frame: WindowFrame, scale: Double, maxW: Double, maxH: Double): WindowFrame {
        if (!(scale.isFinite() && scale > 0.0)) return frame
        val lower = min(1.0, max(MIN_WIDTH / frame.w, MIN_HEIGHT / frame.h))
        val upper = max(lower, min(maxW / frame.w, maxH / frame.h))
        val s = scale.coerceIn(lower, upper)
        val w = frame.w * s
        val h = frame.h * s
        return WindowFrame(frame.x + (frame.w - w) / 2, frame.y + (frame.h - h) / 2, w, h)
    }

    /** Kéo [corner] đi (dx, dy) tính từ [frame] lúc bắt đầu; góc đối diện đứng yên. */
    fun resizeByCorner(frame: WindowFrame, corner: Corner, dx: Double, dy: Double, maxW: Double, maxH: Double): WindowFrame {
        val left = corner == Corner.TOP_LEFT || corner == Corner.BOTTOM_LEFT
        val top = corner == Corner.TOP_LEFT || corner == Corner.TOP_RIGHT
        val w = (frame.w + if (left) -dx else dx).coerceIn(MIN_WIDTH, max(MIN_WIDTH, maxW))
        val h = (frame.h + if (top) -dy else dy).coerceIn(MIN_HEIGHT, max(MIN_HEIGHT, maxH))
        return WindowFrame(if (left) frame.x + frame.w - w else frame.x, if (top) frame.y + frame.h - h else frame.y, w, h)
    }

    /** Tay cầm góc gần [x], [y] nhất trong bán kính [radius] (px); null nếu không chạm góc nào. */
    fun hitCorner(rect: ViewRect, x: Float, y: Float, radius: Float): Corner? =
        listOf(
            Corner.TOP_LEFT to (rect.left to rect.top), Corner.TOP_RIGHT to (rect.right to rect.top),
            Corner.BOTTOM_LEFT to (rect.left to rect.bottom), Corner.BOTTOM_RIGHT to (rect.right to rect.bottom),
        ).map { (c, p) -> c to hypot(x - p.first, y - p.second) }.filter { it.second <= radius }.minByOrNull { it.second }?.first
}
