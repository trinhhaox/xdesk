package vn.xox.xdesk.app.input

import vn.xox.xdesk.transport.InputButton
import vn.xox.xdesk.transport.InputEvents
import vn.xox.xdesk.wire.InputEvent

/**
 * Chạm trực tiếp → con trỏ (giống iOS `GestureInterpreter`):
 * - chạm = click trái (liên tiếp = double/triple), chạm 2 ngón = click phải;
 * - vuốt 1 ngón = cuộn (con trỏ đặt ở chỗ bắt đầu vuốt để cuộn đúng cửa sổ), khoá theo trục chính;
 * - giữ 500 ms rồi kéo = giữ chuột trái và kéo thả; giữ rồi nhả không kéo = click phải;
 * - 2 ngón kéo = cuộn theo pixel; hất rồi nhả (1 hoặc 2 ngón) thì trang trôi tiếp và chậm dần.
 * Không phụ thuộc Android để test được.
 * Đầu ra có `seq` = 0 (do InputSequencer cấp). Không thread-safe: dùng trên một thread (main).
 */
class GestureInterpreter(private var config: GestureConfig) : PointerGestures {
    private sealed interface Mode {
        object Idle : Mode
        class Pending(val id: Int) : Mode
        class Swiping(val id: Int) : Mode // một ngón vuốt: cuộn theo ngón tay
        /** Đã giữ đủ lâu: kéo = kéo thả, nhả = click phải. */
        class Held(val id: Int) : Mode
        class Dragging(val id: Int) : Mode
        object Scrolling : Mode
        /** Đã dùng xong cử chỉ (long press, cuộn kết thúc); chờ nhả hết ngón. */
        object Consumed : Mode
    }

    private class Tap(val point: GesturePoint, val endMs: Long, val count: Int)

    private var mode: Mode = Mode.Idle
    private val touches = LinkedHashMap<Int, GesturePoint>()
    private var start = GesturePoint(0f, 0f)
    private var startMs = 0L
    private var lastTap: Tap? = null
    private var lastCentroid = GesturePoint(0f, 0f)
    private var twoFingerTap: Pair<Long, GesturePoint>? = null
    /** Trục khoá khi vuốt một ngón: (1,0) ngang, (0,1) dọc, (1,1) tự do. */
    private var swipeAxis = GesturePoint(1f, 1f)
    private val momentum = ScrollMomentum()

    override val isHolding: Boolean get() = mode is Mode.Held

    /** Còn việc cần [tick] (chờ nhấn giữ hoặc đang cuộn quán tính) dù không còn ngón nào trên màn hình. */
    val needsTick: Boolean get() = momentum.isActive || touches.isNotEmpty()

    override fun setHostPointsPerViewPoint(scale: Float) {
        config = config.copy(hostPointsPerViewPoint = scale)
    }

    override fun handle(s: TouchSample): List<InputEvent> = when (s.phase) {
        TouchPhase.BEGAN -> began(s.id, GesturePoint(s.x, s.y), s.timeMs)
        TouchPhase.MOVED -> moved(s.id, GesturePoint(s.x, s.y), s.timeMs)
        TouchPhase.ENDED -> ended(s.id, GesturePoint(s.x, s.y), s.timeMs)
        TouchPhase.CANCELLED -> cancelled(s.id)
    }

    /** Gọi định kỳ (~50 ms): giữ đủ lâu thì con trỏ nhảy tới ngón tay, sẵn sàng kéo thả hoặc click phải khi nhả. */
    override fun tick(nowMs: Long): List<InputEvent> {
        momentum.step(nowMs)?.let { (dx, dy) -> return if (dx == 0f && dy == 0f) emptyList() else listOf(InputEvents.scroll(dx, dy)) }
        val m = mode
        if (m !is Mode.Pending || nowMs - startMs < config.longPressMs) return emptyList()
        mode = Mode.Held(m.id)
        return listOf(InputEvents.move(start.x, start.y))
    }

    private fun began(id: Int, p: GesturePoint, timeMs: Long): List<InputEvent> {
        touches[id] = p
        momentum.stop()
        when (val m = mode) {
            Mode.Idle -> { mode = Mode.Pending(id); start = p; startMs = timeMs }
            is Mode.Pending, is Mode.Swiping, is Mode.Held -> {
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

    private fun moved(id: Int, p: GesturePoint, timeMs: Long): List<InputEvent> {
        if (id !in touches) return emptyList()
        touches[id] = p
        return when (val m = mode) {
            is Mode.Pending -> if (m.id == id && distance(p, start) > config.effectiveSlop) {
                mode = Mode.Swiping(id)
                swipeAxis = GestureMath.swipeAxis((p.x - start.x) * config.surfaceWidth, (p.y - start.y) * config.surfaceHeight)
                lastCentroid = start
                listOf(InputEvents.move(start.x, start.y)) + swipe(p, timeMs)
            } else emptyList()
            is Mode.Swiping -> if (m.id == id) swipe(p, timeMs) else emptyList()
            is Mode.Held -> if (m.id == id && distance(p, start) > config.effectiveSlop) {
                mode = Mode.Dragging(id)
                listOf(InputEvents.button(true, start.x, start.y), InputEvents.move(p.x, p.y))
            } else emptyList()
            is Mode.Dragging -> if (m.id == id) listOf(InputEvents.move(p.x, p.y)) else emptyList()
            Mode.Scrolling -> scrolled(timeMs)
            else -> emptyList()
        }
    }

    /** Một ngón vuốt: nội dung đi theo ngón tay (cuộn tự nhiên), chỉ theo trục đã khoá. */
    private fun swipe(p: GesturePoint, timeMs: Long): List<InputEvent> {
        val previous = lastCentroid
        lastCentroid = p
        return scrollBy((p.x - previous.x) * swipeAxis.x, (p.y - previous.y) * swipeAxis.y, timeMs)
    }

    private fun scrolled(timeMs: Long): List<InputEvent> {
        val now = centroid()
        val previous = lastCentroid
        lastCentroid = now
        twoFingerTap?.let { if (distance(now, it.second) > config.effectiveSlop) twoFingerTap = null }
        return scrollBy(now.x - previous.x, now.y - previous.y, timeMs)
    }

    /** Dịch chuẩn hoá → cuộn theo điểm host (đảo chiều nếu tắt cuộn tự nhiên), ghi vận tốc cho cuộn quán tính. */
    private fun scrollBy(nx: Float, ny: Float, timeMs: Long): List<InputEvent> {
        val sign = if (config.naturalScroll) 1f else -1f
        val dx = sign * nx * config.surfaceWidth
        val dy = sign * ny * config.surfaceHeight
        if (dx == 0f && dy == 0f) return emptyList()
        momentum.track(dx, dy, timeMs)
        return listOf(InputEvents.scroll(dx, dy))
    }

    private fun ended(id: Int, p: GesturePoint, timeMs: Long): List<InputEvent> {
        if (id !in touches) return emptyList()
        touches[id] = p
        val events = when (val m = mode) {
            is Mode.Pending -> if (m.id == id) {
                val count = nextTapCount(p, timeMs)
                lastTap = Tap(p, timeMs, count)
                listOf(InputEvents.move(p.x, p.y)) + GestureMath.click(InputButton.LEFT, p, count)
            } else emptyList()
            is Mode.Held -> if (m.id == id) GestureMath.click(if (config.longPressRightClick) InputButton.RIGHT else InputButton.LEFT, start, 1) else emptyList()
            is Mode.Dragging -> if (m.id == id) listOf(InputEvents.button(false, p.x, p.y)) else emptyList()
            is Mode.Swiping -> { if (m.id == id) momentum.release(timeMs); emptyList() }
            Mode.Scrolling -> rightClickAfterTwoFingerTap(timeMs).ifEmpty { momentum.release(timeMs); emptyList() }
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
        return listOf(InputEvents.move(c.x, c.y)) + GestureMath.click(InputButton.RIGHT, c, 1)
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

    private fun nextTapCount(p: GesturePoint, timeMs: Long): Int {
        val last = lastTap ?: return 1
        return if (timeMs - last.endMs <= config.doubleTapMs && distance(p, last.point) <= config.effectiveSlop * 2) last.count + 1 else 1
    }

    private fun centroid() = GestureMath.centroid(touches.values)

    private fun distance(a: GesturePoint, b: GesturePoint) = GestureMath.distance(a, b, config)
}
