package vn.xox.xdesk.app.ui

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerInputScope
import kotlin.math.hypot
import vn.xox.xdesk.app.window.Corner
import vn.xox.xdesk.app.window.WindowAdjustState
import vn.xox.xdesk.app.window.WindowFrameOps
import vn.xox.xdesk.app.window.WindowSpace
import vn.xox.xdesk.wire.WindowFrame

private sealed interface Mode {
    data object Tap : Mode
    data object Ignore : Mode
    data class Drag(val startFrame: WindowFrame) : Mode
    data class ResizeCorner(val startFrame: WindowFrame, val corner: Corner) : Mode
    data class Pinch(val startFrame: WindowFrame, val startDistance: Float) : Mode
}

/**
 * Cử chỉ chỉnh cửa sổ trên lớp phủ: chạm = chọn cửa sổ tại điểm; 1 ngón kéo trong khung = di chuyển; kéo tay cầm góc = đổi cỡ theo góc;
 * 2 ngón chụm/mở = đổi cỡ quanh tâm. Mọi khung mới tính từ khung lúc bắt đầu cử chỉ + tổng độ dời nên không trôi.
 */
internal suspend fun PointerInputScope.windowAdjustGestures(state: WindowAdjustState, space: () -> WindowSpace?, handleHitRadiusPx: Float) {
    val slop = viewConfiguration.touchSlop
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = true)
        val sp = space()
        val start = down.position
        val startFrame = state.frame
        var mode: Mode = if (sp == null) Mode.Ignore else Mode.Tap
        if (sp != null && startFrame != null && state.canResize) {
            WindowFrameOps.hitCorner(sp.frameToView(startFrame), start.x, start.y, handleHitRadiusPx)?.let { mode = Mode.ResizeCorner(startFrame, it) }
        }
        if (mode is Mode.ResizeCorner) state.beginGesture()
        val insideFrame = sp != null && startFrame != null && sp.frameToView(startFrame).contains(start.x, start.y)
        try {
            while (true) {
                val event = awaitPointerEvent()
                val pressed = event.changes.filter { it.pressed }
                if (pressed.isEmpty()) {
                    if (mode is Mode.Tap && sp != null) sp.viewToPoint(start.x, start.y)?.let { state.requestPick(it.first, it.second) }
                    event.changes.forEach { it.consume() }
                    break
                }
                val current = mode
                if (sp != null) {
                    mode = advance(state, sp, current, pressed.map { it.position }, start, startFrame, insideFrame, slop)
                }
                event.changes.forEach { it.consume() }
            }
        } finally {
            state.endGesture()
        }
    }
}

private fun advance(
    state: WindowAdjustState, sp: WindowSpace, mode: Mode, positions: List<Offset>, start: Offset,
    startFrame: WindowFrame?, insideFrame: Boolean, slop: Float,
): Mode {
    if (positions.size >= 2) {
        val begun = mode as? Mode.Pinch
        if (begun == null) {
            if (startFrame == null || !state.canResize || mode is Mode.Ignore) return Mode.Ignore
            state.beginGesture()
            val base = state.frame ?: return Mode.Ignore
            return Mode.Pinch(base, distance(positions).coerceAtLeast(1f))
        }
        state.update(WindowFrameOps.pinch(begun.startFrame, (distance(positions) / begun.startDistance).toDouble(), sp.pointsWidth, sp.pointsHeight))
        return begun
    }
    val position = positions.first()
    val (dx, dy) = sp.deltaToPoints(position.x - start.x, position.y - start.y)
    return when (mode) {
        is Mode.Tap -> if (hypot(position.x - start.x, position.y - start.y) > slop && insideFrame && startFrame != null) {
            state.beginGesture()
            state.update(WindowFrameOps.translate(startFrame, dx, dy))
            Mode.Drag(startFrame)
        } else if (hypot(position.x - start.x, position.y - start.y) > slop) Mode.Ignore else mode
        is Mode.Drag -> mode.also { state.update(WindowFrameOps.translate(mode.startFrame, dx, dy)) }
        is Mode.ResizeCorner -> mode.also {
            state.update(WindowFrameOps.resizeByCorner(mode.startFrame, mode.corner, dx, dy, sp.pointsWidth, sp.pointsHeight))
        }
        is Mode.Pinch, Mode.Ignore -> Mode.Ignore
    }
}

private fun distance(positions: List<Offset>): Float = hypot(positions[0].x - positions[1].x, positions[0].y - positions[1].y)
