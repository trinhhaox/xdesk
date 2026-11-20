package vn.xox.xdesk.app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import vn.xox.xdesk.app.input.GestureConfig
import vn.xox.xdesk.app.input.GestureInterpreter
import vn.xox.xdesk.app.input.TouchPhase
import vn.xox.xdesk.app.input.TouchPhase.BEGAN
import vn.xox.xdesk.app.input.TouchPhase.CANCELLED
import vn.xox.xdesk.app.input.TouchPhase.ENDED
import vn.xox.xdesk.app.input.TouchPhase.MOVED
import vn.xox.xdesk.app.input.TouchSample
import vn.xox.xdesk.transport.InputButton
import vn.xox.xdesk.wire.InputEvent
import vn.xox.xdesk.wire.InputKind

class GestureInterpreterTest {
    private val g = GestureInterpreter(GestureConfig(surfaceWidth = 400f, surfaceHeight = 800f))

    private fun touch(id: Int, phase: TouchPhase, x: Float, y: Float, t: Long) = g.handle(TouchSample(id, x, y, phase, t))
    private fun kinds(events: List<InputEvent>) = events.map { it.kind to it.button }

    @Test
    fun tapIsMoveThenLeftClick() {
        assertTrue(touch(1, BEGAN, 0.5f, 0.5f, 0).isEmpty())
        val events = touch(1, ENDED, 0.5f, 0.5f, 80)
        assertEquals(listOf(InputKind.MOVE to 0, InputKind.DOWN to InputButton.LEFT, InputKind.UP to InputButton.LEFT), kinds(events))
        assertEquals(1f, events[1].dx)
        assertEquals(0.5f, events[0].x)
    }

    @Test
    fun quickSecondTapCountsAsDoubleClick() {
        touch(1, BEGAN, 0.5f, 0.5f, 0); touch(1, ENDED, 0.5f, 0.5f, 50)
        touch(1, BEGAN, 0.5f, 0.5f, 150)
        assertEquals(2f, touch(1, ENDED, 0.5f, 0.5f, 200)[1].dx)
        touch(1, BEGAN, 0.5f, 0.5f, 800)
        assertEquals(1f, touch(1, ENDED, 0.5f, 0.5f, 850)[1].dx, "quá hạn double tap thì đếm lại từ 1")
    }

    @Test
    fun longPressThenReleaseIsRightClick() {
        touch(1, BEGAN, 0.2f, 0.3f, 0)
        assertTrue(g.tick(499).isEmpty())
        assertEquals(listOf(InputKind.MOVE to 0), kinds(g.tick(500)), "giữ đủ lâu: con trỏ tới ngón tay, chưa click")
        assertTrue(g.tick(900).isEmpty())
        val events = touch(1, ENDED, 0.2f, 0.3f, 1000)
        assertEquals(listOf(InputKind.DOWN to InputButton.RIGHT, InputKind.UP to InputButton.RIGHT), kinds(events))
        assertEquals(0.2f, events[0].x)
    }

    @Test
    fun oneFingerSwipeUpAndDownScrolls() {
        touch(1, BEGAN, 0.5f, 0.5f, 0)
        assertTrue(touch(1, MOVED, 0.5f, 0.501f, 10).isEmpty(), "dưới ngưỡng slop vẫn là chạm")
        val start = touch(1, MOVED, 0.5f, 0.4f, 20)
        assertEquals(listOf(InputKind.MOVE, InputKind.SCROLL), start.map { it.kind }, "con trỏ về chỗ bắt đầu vuốt rồi cuộn")
        assertEquals(0.5f, start[0].y)
        assertEquals(0f, start[1].dx)
        assertEquals(-80f, start[1].dy, 0.01f) // 0.1 × 800, nội dung đi theo ngón
        assertEquals(160f, touch(1, MOVED, 0.5f, 0.6f, 30).single().dy, 0.01f)
        assertEquals(0f, touch(1, MOVED, 0.52f, 0.5f, 35).single().dx, "vuốt dọc khoá trục: lệch ngang không cuộn ngang")
        assertTrue(g.tick(2000).isEmpty(), "đang vuốt thì không thành nhấn giữ")
        assertTrue(touch(1, ENDED, 0.5f, 0.6f, 2100).isEmpty())
    }

    @Test
    fun holdThenDragHoldsLeftButtonAndReleases() {
        touch(1, BEGAN, 0.1f, 0.1f, 0)
        g.tick(500)
        val start = touch(1, MOVED, 0.3f, 0.1f, 520)
        assertEquals(listOf(InputKind.DOWN, InputKind.MOVE), start.map { it.kind })
        assertEquals(0.1f, start[0].x)
        assertEquals(listOf(InputKind.MOVE), touch(1, MOVED, 0.4f, 0.1f, 530).map { it.kind })
        val end = touch(1, ENDED, 0.4f, 0.1f, 540)
        assertEquals(listOf(InputKind.UP to InputButton.LEFT), kinds(end))
    }

    @Test
    fun twoFingerDragScrollsInHostPoints() {
        touch(1, BEGAN, 0.4f, 0.4f, 0); touch(2, BEGAN, 0.6f, 0.4f, 5)
        touch(1, MOVED, 0.4f, 0.5f, 10)
        val events = touch(2, MOVED, 0.6f, 0.5f, 11)
        val scroll = events.single()
        assertEquals(InputKind.SCROLL, scroll.kind)
        assertEquals(0f, scroll.dx)
        assertEquals(40f, scroll.dy, 0.01f)
    }

    @Test
    fun twoFingerTapClicksRightAtCentroidOnFirstLift() {
        touch(1, BEGAN, 0.4f, 0.5f, 0); touch(2, BEGAN, 0.6f, 0.5f, 5)
        val events = touch(1, ENDED, 0.4f, 0.5f, 100)
        assertEquals(listOf(InputKind.MOVE to 0, InputKind.DOWN to InputButton.RIGHT, InputKind.UP to InputButton.RIGHT), kinds(events))
        assertEquals(0.5f, events[0].x, 0.001f)
    }

    @Test
    fun cancelDuringDragReleasesButtonAndUnknownTouchIsIgnored() {
        touch(1, BEGAN, 0.1f, 0.1f, 0); g.tick(500); touch(1, MOVED, 0.5f, 0.5f, 510)
        assertEquals(listOf(InputKind.UP to InputButton.LEFT), kinds(touch(1, CANCELLED, 0.5f, 0.5f, 520)))
        assertTrue(touch(9, MOVED, 0.5f, 0.5f, 30).isEmpty())
        assertTrue(touch(9, ENDED, 0.5f, 0.5f, 30).isEmpty())
    }
}
