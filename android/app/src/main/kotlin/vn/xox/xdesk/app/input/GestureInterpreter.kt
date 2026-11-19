package vn.xox.xdesk.app.input

import vn.xox.xdesk.transport.InputButton
import vn.xox.xdesk.transport.InputEvents
import vn.xox.xdesk.wire.InputEvent
import kotlin.math.hypot

enum class TouchPhase { BEGAN, MOVED, ENDED, CANCELLED }

/** Một mẫu chạm: toạ độ chuẩn hoá 0…1 trên khung video, thời gian đơn điệu (ms). */
data class TouchSample(val id: Int, val x: Float, val y: Float, val phase: TouchPhase, val timeMs: Long)

/** `surfaceWidth/Height`: kích thước màn hình host theo điểm; đổi delta chuẩn hoá → pixel và đo ngưỡng di chuyển. */
data class GestureConfig(
    val surfaceWidth: Float,
    val surfaceHeight: Float,
    val longPressMs: Long = 500,
    val doubleTapMs: Long = 300,
    val twoFingerTapMs: Long = 300,
    /** Di chuyển dưới ngưỡng này (điểm host) vẫn tính là chạm. */
    val slop: Float = 8f,
    /** Giữ một ngón đủ [longPressMs] = click phải (cài đặt "nhấn giữ để chuột phải"). */
    val longPressRightClick: Boolean = true,
    /** Cuộn tự nhiên: nội dung đi theo ngón tay; tắt thì đảo chiều. */
    val naturalScroll: Boolean = true,
)

/**
 * Chạm → con trỏ: chạm = click trái (liên tiếp = double/triple), giữ 500 ms hoặc chạm 2 ngón = click phải,
 * 1 ngón kéo = giữ chuột trái và kéo, 2 ngón kéo = cuộn theo pixel. Không phụ thuộc Android để test được.
 * Đầu ra có `seq` = 0 (do InputSequencer cấp). Không thread-safe: dùng trên một thread (main).
 */
class GestureInterpreter(private val config: GestureConfig) : PointerGestures {
    private sealed interface Mode {
        object Idle : Mode
        class Pending(val id: Int) : Mode
        class Dragging(val id: Int) : Mode
        object Scrolling : Mode
        /** Đã dùng xong cử chỉ (long press, cuộn kết thúc); chờ nhả hết ngón. */
        object Consumed : Mode
    }

    private data class Point(val x: Float, val y: Float)
    private class Tap(val point: Point, val endMs: Long, val count: Int)

    private var mode: Mode = Mode.Idle
    private val touches = LinkedHashMap<Int, Point>()
    private var start = Point(0f, 0f)
    private var startMs = 0L
    private var lastTap: Tap? = null
    private var lastCentroid = Point(0f, 0f)
    private var twoFingerTap: Pair<Long, Point>? = null

    override fun handle(s: TouchSample): List<InputEvent> = when (s.phase) {
        TouchPhase.BEGAN -> began(s.id, Point(s.x, s.y), s.timeMs)
        TouchPhase.MOVED -> moved(s.id, Point(s.x, s.y))
        TouchPhase.ENDED -> ended(s.id, Point(s.x, s.y), s.timeMs)
        TouchPhase.CANCELLED -> cancelled(s.id)
    }

    /** Gọi định kỳ (~50 ms) để phát click phải khi giữ đủ lâu. */
    override fun tick(nowMs: Long): List<InputEvent> {
        if (!config.longPressRightClick || mode !is Mode.Pending || nowMs - startMs < config.longPressMs) return emptyList()
        mode = Mode.Consumed
        return listOf(InputEvents.move(start.x, start.y)) + click(InputButton.RIGHT, start, 1)
    }

    private fun began(id: Int, p: Point, timeMs: Long): List<InputEvent> {
        touches[id] = p
        when (val m = mode) {
            Mode.Idle -> { mode = Mode.Pending(id); start = p; startMs = timeMs }
            is Mode.Pending -> {
                mode = Mode.Scrolling
                lastCentroid = centroid()
                twoFingerTap = if (touches.size == 2) timeMs to lastCentroid else null
            }
            is Mode.Dragging -> {
                mode = Mode.Scrolling
                twoFingerTap = null
                lastCentroid = centroid()
                return listOf(releaseDrag(m.id))
            }
            else -> Unit
        }
        return emptyList()
    }

    private fun moved(id: Int, p: Point): List<InputEvent> {
        if (id !in touches) return emptyList()
        touches[id] = p
        return when (val m = mode) {
            is Mode.Pending -> if (m.id == id && distance(p, start) > config.slop) {
                mode = Mode.Dragging(id)
                listOf(InputEvents.move(start.x, start.y), InputEvents.button(true, start.x, start.y), InputEvents.move(p.x, p.y))
            } else emptyList()
            is Mode.Dragging -> if (m.id == id) listOf(InputEvents.move(p.x, p.y)) else emptyList()
            Mode.Scrolling -> scrolled()
            else -> emptyList()
        }
    }

    private fun scrolled(): List<InputEvent> {
        val now = centroid()
        val previous = lastCentroid
        lastCentroid = now
        twoFingerTap?.let { if (distance(now, it.second) > config.slop) twoFingerTap = null }
        val sign = if (config.naturalScroll) 1f else -1f
        val dx = sign * (now.x - previous.x) * config.surfaceWidth
        val dy = sign * (now.y - previous.y) * config.surfaceHeight
        return if (dx == 0f && dy == 0f) emptyList() else listOf(InputEvents.scroll(dx, dy))
    }

    private fun ended(id: Int, p: Point, timeMs: Long): List<InputEvent> {
        if (id !in touches) return emptyList()
        touches[id] = p
        val events = when (val m = mode) {
            is Mode.Pending -> if (m.id == id) {
                val count = nextTapCount(p, timeMs)
                lastTap = Tap(p, timeMs, count)
                listOf(InputEvents.move(p.x, p.y)) + click(InputButton.LEFT, p, count)
            } else emptyList()
            is Mode.Dragging -> if (m.id == id) listOf(InputEvents.button(false, p.x, p.y)) else emptyList()
            Mode.Scrolling -> rightClickAfterTwoFingerTap(timeMs)
            else -> emptyList()
        }
        touches.remove(id)
        mode = if (touches.isEmpty()) Mode.Idle else Mode.Consumed
        return events
    }

    private fun rightClickAfterTwoFingerTap(timeMs: Long): List<InputEvent> {
        val tap = twoFingerTap ?: return emptyList()
        if (touches.size != 2 || timeMs - tap.first > config.twoFingerTapMs) return emptyList()
        twoFingerTap = null
        val c = centroid()
        return listOf(InputEvents.move(c.x, c.y)) + click(InputButton.RIGHT, c, 1)
    }

    private fun cancelled(id: Int): List<InputEvent> {
        if (id !in touches) return emptyList()
        val m = mode
        val events = if (m is Mode.Dragging && m.id == id) listOf(releaseDrag(id)) else emptyList()
        touches.remove(id)
        mode = if (touches.isEmpty()) Mode.Idle else Mode.Consumed
        return events
    }

    private fun releaseDrag(id: Int): InputEvent {
        val p = touches[id] ?: start
        return InputEvents.button(false, p.x, p.y)
    }

    private fun click(button: Int, p: Point, count: Int) = listOf(
        InputEvents.button(true, p.x, p.y, button, count), InputEvents.button(false, p.x, p.y, button, count),
    )

    private fun nextTapCount(p: Point, timeMs: Long): Int {
        val last = lastTap ?: return 1
        return if (timeMs - last.endMs <= config.doubleTapMs && distance(p, last.point) <= config.slop * 2) last.count + 1 else 1
    }

    private fun centroid(): Point = Point(touches.values.map { it.x }.average().toFloat(), touches.values.map { it.y }.average().toFloat())

    private fun distance(a: Point, b: Point) = hypot((a.x - b.x) * config.surfaceWidth, (a.y - b.y) * config.surfaceHeight)
}
