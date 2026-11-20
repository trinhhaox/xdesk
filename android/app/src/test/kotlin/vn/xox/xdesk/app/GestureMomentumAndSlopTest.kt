package vn.xox.xdesk.app

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import vn.xox.xdesk.app.input.GestureConfig
import vn.xox.xdesk.app.input.GestureInterpreter
import vn.xox.xdesk.app.input.TouchPhase
import vn.xox.xdesk.app.input.TouchPhase.BEGAN
import vn.xox.xdesk.app.input.TouchPhase.ENDED
import vn.xox.xdesk.app.input.TouchPhase.MOVED
import vn.xox.xdesk.app.input.TouchSample
import vn.xox.xdesk.wire.InputKind

/** Cuộn quán tính, ngưỡng chạm theo dp màn hình và trạng thái nhấn giữ (cho rung). */
class GestureMomentumAndSlopTest {
    private fun GestureInterpreter.touch(id: Int, phase: TouchPhase, x: Float, y: Float, t: Long) = handle(TouchSample(id, x, y, phase, t))

    private fun flick(g: GestureInterpreter, releaseAt: Long = 50) {
        g.touch(1, BEGAN, 0.5f, 0.8f, 0)
        listOf(0.7f, 0.6f, 0.5f, 0.4f).forEachIndexed { i, y -> g.touch(1, MOVED, 0.5f, y, 10L * (i + 1)) }
        g.touch(1, ENDED, 0.5f, 0.4f, releaseAt)
    }

    @Test
    fun flickKeepsScrollingThenSlowsDownAndStops() {
        val g = GestureInterpreter(GestureConfig(1000f, 500f))
        flick(g)
        assertTrue(g.needsTick)
        val first = g.tick(100).single()
        val second = g.tick(150).single()
        assertEquals(InputKind.SCROLL, first.kind)
        assertTrue(first.dy < 0, "trôi tiếp cùng chiều vuốt lên")
        assertTrue(abs(second.dy) < abs(first.dy), "chậm dần")
        var t = 200L
        while (g.needsTick && t < 10_000) { g.tick(t); t += 50 }
        assertFalse(g.needsTick, "dừng hẳn sau vài giây")
        assertTrue(g.tick(t + 50).isEmpty())
    }

    @Test
    fun fingerThatStopsBeforeReleaseDoesNotGlide() {
        val g = GestureInterpreter(GestureConfig(1000f, 500f))
        flick(g, releaseAt = 400)
        assertFalse(g.needsTick)
        assertTrue(g.tick(450).isEmpty())
    }

    @Test
    fun touchingAgainStopsTheGlide() {
        val g = GestureInterpreter(GestureConfig(1000f, 500f))
        flick(g)
        g.touch(2, BEGAN, 0.5f, 0.5f, 60)
        assertTrue(g.tick(100).isEmpty())
        assertEquals(listOf(InputKind.MOVE, InputKind.DOWN, InputKind.UP), g.touch(2, ENDED, 0.5f, 0.5f, 120).map { it.kind })
    }

    @Test
    fun slopFollowsTheFingerNotTheHostScreen() {
        // Mac 2000 điểm hiện trên 400 dp: 1 dp = 5 điểm host → ngưỡng 50 điểm host.
        val g = GestureInterpreter(GestureConfig(2000f, 1000f, hostPointsPerViewPoint = 5f))
        g.touch(1, BEGAN, 0.5f, 0.5f, 0)
        assertTrue(g.touch(1, MOVED, 0.5f, 0.53f, 20).isEmpty(), "30 điểm host = 6 dp dưới ngón: vẫn là chạm")
        assertEquals(listOf(InputKind.MOVE, InputKind.DOWN, InputKind.UP), g.touch(1, ENDED, 0.5f, 0.53f, 60).map { it.kind })
    }

    @Test
    fun zoomChangeUpdatesSlopWithoutLosingState() {
        val g = GestureInterpreter(GestureConfig(2000f, 1000f))
        g.touch(1, BEGAN, 0.5f, 0.5f, 0)
        g.setHostPointsPerViewPoint(5f)
        assertTrue(g.touch(1, MOVED, 0.5f, 0.53f, 20).isEmpty())
        g.setHostPointsPerViewPoint(1f)
        assertEquals(listOf(InputKind.MOVE, InputKind.SCROLL), g.touch(1, MOVED, 0.5f, 0.53f, 30).map { it.kind })
    }

    @Test
    fun isHoldingTurnsOnAfterLongPressAndOffWhenDragging() {
        val g = GestureInterpreter(GestureConfig(1000f, 500f))
        g.touch(1, BEGAN, 0.2f, 0.2f, 0)
        assertFalse(g.isHolding)
        g.tick(500)
        assertTrue(g.isHolding)
        g.touch(1, MOVED, 0.4f, 0.2f, 520)
        assertFalse(g.isHolding)
    }
}
