package vn.xox.xdesk.app.input

import vn.xox.xdesk.transport.InputEvents
import vn.xox.xdesk.wire.InputEvent
import kotlin.math.abs
import kotlin.math.hypot

/** Điểm chuẩn hoá 0…1 trên khung video. */
internal data class GesturePoint(val x: Float, val y: Float)

/** Phép tính thuần cho bộ diễn giải cử chỉ (không giữ trạng thái). */
internal object GestureMath {
    fun click(button: Int, p: GesturePoint, count: Int): List<InputEvent> = listOf(
        InputEvents.button(true, p.x, p.y, button, count), InputEvents.button(false, p.x, p.y, button, count),
    )

    /** Hướng vuốt rõ ràng (gấp đôi trục kia) thì khoá theo trục đó: (1,0) ngang, (0,1) dọc, (1,1) tự do. */
    fun swipeAxis(dx: Float, dy: Float): GesturePoint = when {
        abs(dy) >= 2 * abs(dx) -> GesturePoint(0f, 1f)
        abs(dx) >= 2 * abs(dy) -> GesturePoint(1f, 0f)
        else -> GesturePoint(1f, 1f)
    }

    fun centroid(points: Collection<GesturePoint>) =
        GesturePoint(points.map { it.x }.average().toFloat(), points.map { it.y }.average().toFloat())

    /** Khoảng cách theo điểm host. */
    fun distance(a: GesturePoint, b: GesturePoint, config: GestureConfig) =
        hypot((a.x - b.x) * config.surfaceWidth, (a.y - b.y) * config.surfaceHeight)
}
