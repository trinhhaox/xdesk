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
    fun longPressBecomesRightClickOnce() {
        touch(1, BEGAN, 0.2f, 0.3f, 0)
        assertTrue(g.tick(499).isEmpty())
        val events = g.tick(500)
        assertEquals(listOf(InputKind.MOVE to 0, InputKind.DOWN to InputButton.RIGHT, InputKind.UP to InputButton.RIGHT), kinds(events))
        assertTrue(g.tick(900).isEmpty())
        assertTrue(touch(1, ENDED, 0.2f, 0.3f, 1000).isEmpty(), "nhả sau long press không click thêm")
    }

    @Test
    fun oneFingerDragHoldsLeftButtonAndReleases() {
        touch(1, BEGAN, 0.1f, 0.1f, 0)
        assertTrue(touch(1, MOVED, 0.101f, 0.1f, 10).isEmpty(), "dưới ngưỡng slop vẫn là chạm")
        val start = touch(1, MOVED, 0.3f, 0.1f, 20)
        assertEquals(listOf(InputKind.MOVE, InputKind.DOWN, InputKind.MOVE), start.map { it.kind })
        assertEquals(listOf(InputKind.MOVE), touch(1, MOVED, 0.4f, 0.1f, 30).map { it.kind })
        val end = touch(1, ENDED, 0.4f, 0.1f, 40)
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
        touch(1, BEGAN, 0.1f, 0.1f, 0); touch(1, MOVED, 0.5f, 0.5f, 10)
        assertEquals(listOf(InputKind.UP to InputButton.LEFT), kinds(touch(1, CANCELLED, 0.5f, 0.5f, 20)))
        assertTrue(touch(9, MOVED, 0.5f, 0.5f, 30).isEmpty())
        assertTrue(touch(9, ENDED, 0.5f, 0.5f, 30).isEmpty())
    }
}
