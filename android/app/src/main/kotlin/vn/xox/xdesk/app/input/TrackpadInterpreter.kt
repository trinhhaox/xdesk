package vn.xox.xdesk.app.input

import vn.xox.xdesk.transport.InputButton
import vn.xox.xdesk.transport.InputEvents
import vn.xox.xdesk.wire.InputEvent
import kotlin.math.hypot

/** `surfaceWidth/Height`: màn hình host theo điểm. `tapSlop`: tỉ lệ chiều rộng khung; ngón di chuyển ít hơn vẫn là chạm. */
data class TrackpadConfig(
    val surfaceWidth: Float,
    val surfaceHeight: Float,
    val speed: Float = 1f,
    val naturalScroll: Boolean = true,
    val longPressRightClick: Boolean = true,
    val longPressMs: Long = 500,
    val doubleTapMs: Long = 300,
    val twoFingerTapMs: Long = 300,
    val tapSlop: Float = 0.02f,
)

/**
 * Chạm kiểu trackpad: 1 ngón trượt = di chuyển con trỏ tương đối (có gia tốc), chạm = click tại con trỏ,
 * 2 ngón chạm = click phải, 2 ngón trượt = cuộn, chạm-rồi-chạm-giữ-và-trượt = kéo. Wire chỉ có toạ độ tuyệt đối
 * nên viewer tự giữ vị trí con trỏ (0…1, ép vào khung). Không phụ thuộc Android để test được; một thread (main).
 */
class TrackpadInterpreter(private val config: TrackpadConfig, start: Pair<Float, Float> = 0.5f to 0.5f) : PointerGestures {
    private sealed interface Mode {
        object Idle : Mode
        class Pending(val id: Int, val secondTap: Boolean) : Mode
        class Moving(val id: Int) : Mode
        class Dragging(val id: Int) : Mode
        object Scrolling : Mode
        object Consumed : Mode
    }

    private data class Point(val x: Float, val y: Float)
    private class Tap(val endMs: Long, val count: Int)

    private var mode: Mode = Mode.Idle
    private val touches = LinkedHashMap<Int, Point>()
    private var startPoint = Point(0f, 0f)
    private var startMs = 0L
    private var previous = Point(0f, 0f)
    private var previousMs = 0L
    private var velocity = 0f
    private var lastTap: Tap? = null
    private var lastCentroid = Point(0f, 0f)
    private var twoFingerTap: Pair<Long, Point>? = null
    private var position = Point(start.first.coerceIn(0f, 1f), start.second.coerceIn(0f, 1f))

    override val cursor: Pair<Float, Float> get() = position.x to position.y

    override fun handle(s: TouchSample): List<InputEvent> = when (s.phase) {
        TouchPhase.BEGAN -> began(s.id, Point(s.x, s.y), s.timeMs)
        TouchPhase.MOVED -> moved(s.id, Point(s.x, s.y), s.timeMs)
        TouchPhase.ENDED -> ended(s.id, s.timeMs)
        TouchPhase.CANCELLED -> cancelled(s.id)
    }

    override fun tick(nowMs: Long): List<InputEvent> {
        val m = mode
        if (!config.longPressRightClick || m !is Mode.Pending || m.secondTap || nowMs - startMs < config.longPressMs) return emptyList()
        mode = Mode.Consumed
        lastTap = null
        return clickAtCursor(InputButton.RIGHT, 1)
    }

    private fun began(id: Int, p: Point, timeMs: Long): List<InputEvent> {
        touches[id] = p
        when (val m = mode) {
            Mode.Idle -> {
                val second = lastTap?.let { timeMs - it.endMs <= config.doubleTapMs } ?: false
                mode = Mode.Pending(id, second)
                startPoint = p; previous = p; previousMs = timeMs; startMs = timeMs; velocity = 0f
            }
            is Mode.Pending, is Mode.Moving -> startScrolling(m is Mode.Pending && touches.size == 2, timeMs)
            is Mode.Dragging -> {
                startScrolling(false, timeMs)
                return listOf(InputEvents.button(false, position.x, position.y))
            }
            else -> Unit
        }
        return emptyList()
    }

    private fun moved(id: Int, p: Point, timeMs: Long): List<InputEvent> {
        if (id !in touches) return emptyList()
        touches[id] = p
        return when (val m = mode) {
            is Mode.Pending -> if (m.id == id && distance(p, startPoint) > config.tapSlop) {
                lastTap = null
                val head = if (m.secondTap) {
                    mode = Mode.Dragging(id)
                    listOf(InputEvents.move(position.x, position.y), InputEvents.button(true, position.x, position.y))
                } else {
                    mode = Mode.Moving(id)
                    emptyList()
                }
                head + moveCursor(p, timeMs)
            } else emptyList()
            is Mode.Moving -> if (m.id == id) moveCursor(p, timeMs) else emptyList()
            is Mode.Dragging -> if (m.id == id) moveCursor(p, timeMs) else emptyList()
            Mode.Scrolling -> scrolled()
            else -> emptyList()
        }
    }

    private fun ended(id: Int, timeMs: Long): List<InputEvent> {
        if (id !in touches) return emptyList()
        val events = when (val m = mode) {
            is Mode.Pending -> if (m.id == id) {
                val count = if (m.secondTap) (lastTap?.count ?: 0) + 1 else 1
                lastTap = Tap(timeMs, count)
                clickAtCursor(InputButton.LEFT, count)
            } else emptyList()
            is Mode.Dragging -> if (m.id == id) listOf(InputEvents.button(false, position.x, position.y)) else emptyList()
            Mode.Scrolling -> rightClickAfterTwoFingerTap(timeMs)
            else -> emptyList()
        }
        touches.remove(id)
        mode = if (touches.isEmpty()) Mode.Idle else Mode.Consumed
        return events
    }

    private fun cancelled(id: Int): List<InputEvent> {
        if (id !in touches) return emptyList()
        val m = mode
        val events = if (m is Mode.Dragging && m.id == id) listOf(InputEvents.button(false, position.x, position.y)) else emptyList()
        touches.remove(id)
        mode = if (touches.isEmpty()) Mode.Idle else Mode.Consumed
        return events
    }

    private fun startScrolling(asTap: Boolean, timeMs: Long) {
        mode = Mode.Scrolling
        lastCentroid = centroid()
        twoFingerTap = if (asTap) timeMs to lastCentroid else null
    }

    private fun rightClickAfterTwoFingerTap(timeMs: Long): List<InputEvent> {
        val tap = twoFingerTap ?: return emptyList()
        if (touches.size != 2 || timeMs - tap.first > config.twoFingerTapMs) return emptyList()
        twoFingerTap = null
        return clickAtCursor(InputButton.RIGHT, 1)
    }

    private fun scrolled(): List<InputEvent> {
        val now = centroid()
        val previousCentroid = lastCentroid
        lastCentroid = now
        twoFingerTap?.let { if (distance(now, it.second) > config.tapSlop) twoFingerTap = null }
        val sign = if (config.naturalScroll) 1f else -1f
        val dx = sign * (now.x - previousCentroid.x) * config.surfaceWidth
        val dy = sign * (now.y - previousCentroid.y) * config.surfaceHeight
        return if (dx == 0f && dy == 0f) emptyList() else listOf(InputEvents.scroll(dx, dy))
    }

    /** Dời con trỏ theo độ dời của ngón nhân gia tốc theo vận tốc (làm mượt 50/50 để bớt nhiễu mẫu). */
    private fun moveCursor(p: Point, timeMs: Long): List<InputEvent> {
        val dx = p.x - previous.x
        val dy = p.y - previous.y
        val dt = maxOf(4L, timeMs - previousMs) / 1000f
        velocity = (velocity + distance(p, previous) / dt) / 2f
        previous = p
        previousMs = timeMs
        val gain = PointerAcceleration.gain(velocity, config.speed)
        val next = Point((position.x + dx * gain).coerceIn(0f, 1f), (position.y + dy * gain).coerceIn(0f, 1f))
        if (next == position) return emptyList()
        position = next
        return listOf(InputEvents.move(next.x, next.y))
    }

    private fun clickAtCursor(button: Int, count: Int) = listOf(
        InputEvents.move(position.x, position.y),
        InputEvents.button(true, position.x, position.y, button, count),
        InputEvents.button(false, position.x, position.y, button, count),
    )

    private fun centroid() = Point(touches.values.map { it.x }.average().toFloat(), touches.values.map { it.y }.average().toFloat())

    /** Khoảng cách theo tỉ lệ chiều rộng màn hình host (chiều dọc đổi theo khung hình). */
    private fun distance(a: Point, b: Point) = hypot(a.x - b.x, (a.y - b.y) * config.surfaceHeight / maxOf(1f, config.surfaceWidth))
}
