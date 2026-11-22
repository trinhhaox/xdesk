package vn.xox.xdesk.app

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import vn.xox.xdesk.app.input.VideoContentMapper
import vn.xox.xdesk.app.input.VideoViewport
import vn.xox.xdesk.app.window.Corner
import vn.xox.xdesk.app.window.ViewRect
import vn.xox.xdesk.app.window.WindowAdjustState
import vn.xox.xdesk.app.window.WindowFrameOps
import vn.xox.xdesk.app.window.WindowSpace
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.WindowAdjustOp
import vn.xox.xdesk.wire.WindowFrame
import vn.xox.xdesk.wire.WindowPreset

/** Video 2000×1000 px, scale 2 → 1000×500 điểm, đặt trong view vuông 1000×1000 (letterbox trên/dưới 250 px). */
class WindowAdjustTest {
    private val mapper = checkNotNull(VideoContentMapper.of(1000f, 1000f, 2000f, 1000f))
    private val points = 1000.0 to 500.0
    private fun space(viewport: VideoViewport = VideoViewport.IDENTITY, panY: Float = 0f) =
        checkNotNull(WindowSpace.of(mapper, viewport, panY, points))

    private fun near(a: Double, b: Double, eps: Double = 1e-3) = abs(a - b) < eps

    @Test fun letterboxedTouchMapsToPointsAndBlackBandIsRejected() {
        val (x, y) = checkNotNull(space().viewToPoint(500f, 500f))
        assertTrue(near(x, 500.0) && near(y, 250.0))
        val (cx, cy) = checkNotNull(space().viewToPoint(250f, 375f))
        assertTrue(near(cx, 250.0) && near(cy, 125.0))
        assertNull(space().viewToPoint(500f, 100f))
    }

    @Test fun zoomedTouchMapsThroughViewport() {
        val zoomed = VideoViewport(zoom = 2f)
        val (x, y) = checkNotNull(space(zoomed).viewToPoint(750f, 500f))
        assertTrue(near(x, 625.0) && near(y, 250.0))
        val (vx, vy) = space(zoomed).pointToView(625.0, 250.0)
        assertTrue(abs(vx - 750f) < 0.01f && abs(vy - 500f) < 0.01f)
    }

    @Test fun keyboardPanShiftsBothDirectionsConsistently() {
        val sp = space(panY = 100f)
        val (px, py) = checkNotNull(sp.viewToPoint(500f, 400f)) // vy = 500 → giữa video
        assertTrue(near(px, 500.0) && near(py, 250.0))
        assertEquals(400f, sp.pointToView(500.0, 250.0).second, 0.01f)
    }

    @Test fun deltaScalesByZoomAndLetterbox() {
        val (dx, dy) = space().deltaToPoints(100f, 50f)
        assertTrue(near(dx, 100.0) && near(dy, 50.0))
        val (zx, zy) = space(VideoViewport(zoom = 2f)).deltaToPoints(100f, 50f)
        assertTrue(near(zx, 50.0) && near(zy, 25.0))
    }

    @Test fun frameToViewRoundTripsLetterbox() {
        val r = space().frameToView(WindowFrame(100.0, 50.0, 400.0, 200.0))
        assertEquals(ViewRect(100f, 300f, 500f, 500f), r)
        assertTrue(r.contains(300f, 400f) && !r.contains(600f, 400f))
    }

    @Test fun spaceIsNullWithoutValidGeometry() {
        assertNull(WindowSpace.of(null, VideoViewport.IDENTITY, 0f, points))
        assertNull(WindowSpace.of(mapper, VideoViewport.IDENTITY, 0f, null))
        assertNull(WindowSpace.of(mapper, VideoViewport.IDENTITY, 0f, 0.0 to 500.0))
    }

    @Test fun dragIsPureTranslation() {
        val f = WindowFrame(100.0, 100.0, 400.0, 300.0)
        assertEquals(WindowFrame(130.0, 70.0, 400.0, 300.0), WindowFrameOps.translate(f, 30.0, -30.0))
    }

    @Test fun pinchScalesAroundCenter() {
        val out = WindowFrameOps.pinch(WindowFrame(100.0, 100.0, 400.0, 300.0), 1.5, 1000.0, 800.0)
        assertEquals(WindowFrame(0.0, 25.0, 600.0, 450.0), out)
    }

    @Test fun pinchClampsToMinAndScreen() {
        val small = WindowFrameOps.pinch(WindowFrame(100.0, 100.0, 400.0, 300.0), 0.1, 1000.0, 800.0)
        assertEquals(WindowFrameOps.MIN_WIDTH, small.w, 1e-9)
        assertEquals(WindowFrameOps.MIN_HEIGHT, small.h, 1e-9)
        assertTrue(near(small.x + small.w / 2, 300.0) && near(small.y + small.h / 2, 250.0))
        val big = WindowFrameOps.pinch(WindowFrame(100.0, 100.0, 400.0, 300.0), 10.0, 1000.0, 600.0)
        assertEquals(800.0, big.w, 1e-9)
        assertEquals(600.0, big.h, 1e-9)
    }

    @Test fun cornerDragKeepsOppositeCornerFixed() {
        val f = WindowFrame(100.0, 100.0, 400.0, 300.0)
        assertEquals(WindowFrame(100.0, 100.0, 450.0, 340.0), WindowFrameOps.resizeByCorner(f, Corner.BOTTOM_RIGHT, 50.0, 40.0, 1000.0, 800.0))
        assertEquals(WindowFrame(60.0, 80.0, 440.0, 320.0), WindowFrameOps.resizeByCorner(f, Corner.TOP_LEFT, -40.0, -20.0, 1000.0, 800.0))
        // kéo góc trên-trái vào quá mức tối thiểu: góc dưới-phải vẫn đứng yên ở (500, 400)
        val squeezed = WindowFrameOps.resizeByCorner(f, Corner.TOP_LEFT, 380.0, 290.0, 1000.0, 800.0)
        assertEquals(WindowFrame(300.0, 250.0, 200.0, 150.0), squeezed)
    }

    @Test fun hitCornerPicksNearestWithinRadius() {
        val rect = ViewRect(100f, 100f, 500f, 400f)
        assertEquals(Corner.TOP_RIGHT, WindowFrameOps.hitCorner(rect, 490f, 110f, 40f))
        assertEquals(Corner.BOTTOM_LEFT, WindowFrameOps.hitCorner(rect, 95f, 405f, 40f))
        assertNull(WindowFrameOps.hitCorner(rect, 300f, 250f, 40f))
    }

    private class Harness {
        val adjusts = mutableListOf<ControlMessage.WindowAdjust>()
        val toasts = mutableListOf<String>()
        val picks = mutableListOf<Pair<Double, Double>>()
        val state = WindowAdjustState({ x, y -> picks += x to y }, { adjusts += it }, { toasts += it }).also { it.enter() }
        fun select(frame: WindowFrame, id: Long = 7, resizable: Boolean = true) =
            state.onSelected(ControlMessage.WindowSelected(true, id, "Safari", "t", frame, resizable, null))
    }

    @Test fun dragDeltasAreCoalescedAndRateLimited() {
        val h = Harness()
        h.select(WindowFrame(100.0, 100.0, 400.0, 300.0))
        h.state.beginGesture()
        h.state.update(WindowFrame(110.0, 100.0, 400.0, 300.0))
        h.state.update(WindowFrame(130.0, 120.0, 400.0, 300.0))
        h.state.flush(1_000_000_000L)
        h.state.update(WindowFrame(140.0, 120.0, 400.0, 300.0))
        h.state.flush(1_005_000_000L) // quá sớm: giữ lại
        assertEquals(1, h.adjusts.size)
        assertEquals(WindowAdjustOp.MOVE, h.adjusts[0].op)
        assertEquals(30.0, h.adjusts[0].dx)
        assertEquals(20.0, h.adjusts[0].dy)
        h.state.flush(1_020_000_000L)
        assertEquals(10.0, h.adjusts[1].dx)
        assertEquals(0.0, h.adjusts[1].dy)
        assertEquals(WindowFrame(140.0, 120.0, 400.0, 300.0), h.state.frame)
    }

    @Test fun resizeSendsAbsoluteSizeThenCenterShiftOnNextTick() {
        val h = Harness()
        h.select(WindowFrame(100.0, 100.0, 400.0, 300.0))
        h.state.beginGesture()
        h.state.update(WindowFrameOps.resizeByCorner(h.state.frame!!, Corner.BOTTOM_RIGHT, 100.0, 100.0, 1000.0, 800.0))
        h.state.flush(1_000_000_000L)
        h.state.flush(1_020_000_000L)
        assertEquals(WindowAdjustOp.RESIZE, h.adjusts[0].op)
        assertEquals(500.0, h.adjusts[0].w)
        assertEquals(400.0, h.adjusts[0].h)
        assertEquals(WindowAdjustOp.MOVE, h.adjusts[1].op)
        assertEquals(50.0, h.adjusts[1].dx)
        assertEquals(50.0, h.adjusts[1].dy)
    }

    @Test fun hostFrameIsIgnoredWhileGestureOrPendingThenAdopted() {
        val h = Harness()
        h.select(WindowFrame(100.0, 100.0, 400.0, 300.0))
        h.state.beginGesture()
        h.state.update(WindowFrame(150.0, 100.0, 400.0, 300.0))
        h.select(WindowFrame(90.0, 100.0, 400.0, 300.0))
        assertEquals(150.0, h.state.frame?.x)
        h.state.flush(1_000_000_000L)
        h.state.endGesture()
        h.select(WindowFrame(150.0, 100.0, 400.0, 300.0))
        assertEquals(150.0, h.state.frame?.x)
    }

    @Test fun failureShowsToastAndKeepsSelection() {
        val h = Harness()
        h.select(WindowFrame(100.0, 100.0, 400.0, 300.0))
        h.state.onSelected(ControlMessage.WindowSelected.failure("Không có cửa sổ ở đây"))
        assertEquals(listOf("Không có cửa sổ ở đây"), h.toasts)
        assertNotNull(h.state.selection?.windowId)
    }

    @Test fun presetNeedsSelectionAndExitClearsIt() {
        val h = Harness()
        h.state.applyPreset(WindowPreset.FILL)
        assertTrue(h.adjusts.isEmpty())
        h.select(WindowFrame(100.0, 100.0, 400.0, 300.0))
        h.state.applyPreset(WindowPreset.LEFT)
        assertEquals(WindowPreset.LEFT, h.adjusts.single().preset)
        h.state.exit()
        assertTrue(!h.state.active && h.state.frame == null && h.state.selection == null)
    }

    @Test fun nonResizableWindowCannotResize() {
        val h = Harness()
        h.select(WindowFrame(100.0, 100.0, 400.0, 300.0), resizable = false)
        assertTrue(h.state.canAdjust && !h.state.canResize)
    }
}
