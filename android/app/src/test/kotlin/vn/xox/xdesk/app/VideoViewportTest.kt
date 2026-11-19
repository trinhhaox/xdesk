package vn.xox.xdesk.app

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import vn.xox.xdesk.app.input.VideoContentMapper
import vn.xox.xdesk.app.input.VideoViewport

/** Mac 16:10 (2560×1600) trong điện thoại dọc 393×852: video letterbox, rộng kín view (bản sao của VideoViewportTests bên Swift). */
class VideoViewportTest {
    private val portrait = checkNotNull(VideoContentMapper.of(393f, 852f, 2560f, 1600f))
    private fun near(a: Pair<Float, Float>, b: Pair<Float, Float>, eps: Float = 0.01f) = abs(a.first - b.first) < eps && abs(a.second - b.second) < eps

    @Test fun identityMapsOneToOne() = assertTrue(near(VideoViewport.IDENTITY.toBase(100f, 400f, portrait), 100f to 400f))

    @Test fun letterboxTouchesInBlackBandsAreRejected() {
        assertNull(portrait.normalize(100f, 10f))
        assertNotNull(portrait.normalize(100f, 426f))
        assertEquals(0f, checkNotNull(portrait.normalize(100f, 10f, clamping = true)).second)
    }

    @Test fun zoomKeepsFocusPointFixedAndMapsToMacCoordinates() {
        val before = checkNotNull(portrait.normalize(300f, 426f))
        val zoomed = VideoViewport.IDENTITY.zoomed(3f, 300f, 426f, portrait)
        assertEquals(3f, zoomed.zoom)
        val (bx, by) = zoomed.toBase(300f, 426f, portrait)
        val after = checkNotNull(portrait.normalize(bx, by))
        assertTrue(near(before, after, 1e-4f))
    }

    @Test fun zoomedCornersReachMacCorners() {
        var v = VideoViewport.IDENTITY.zoomed(4f, 196.5f, 426f, portrait).panned(-10_000f, 0f, portrait)
        val (rx, ry) = v.toBase(393f, 426f, portrait)
        assertTrue(abs(checkNotNull(portrait.normalize(rx, ry)).first - 1f) < 1e-4f)
        v = v.panned(10_000f, 0f, portrait)
        val (lx, ly) = v.toBase(0f, 426f, portrait)
        assertTrue(abs(checkNotNull(portrait.normalize(lx, ly)).first) < 1e-4f)
    }

    @Test fun roundTripBaseView() {
        val v = VideoViewport.IDENTITY.zoomed(2.5f, 120f, 300f, portrait)
        val (x, y) = v.toView(77f, 413f, portrait)
        assertTrue(near(v.toBase(x, y, portrait), 77f to 413f))
    }

    @Test fun zoomIsClampedToRangeAndRejectsNaN() {
        assertEquals(VideoViewport.MAX_ZOOM, VideoViewport.IDENTITY.zoomed(100f, 10f, 10f, portrait).zoom)
        assertTrue(VideoViewport.IDENTITY.zoomed(0.1f, 10f, 10f, portrait).isIdentity)
        assertTrue(VideoViewport.IDENTITY.zoomed(Float.NaN, 10f, 10f, portrait).isIdentity)
    }

    @Test fun panCannotExposeGapsAndShortAxisStaysCentered() {
        val v = VideoViewport.IDENTITY.zoomed(2f, 196.5f, 426f, portrait).panned(5000f, 5000f, portrait)
        assertEquals(0f, v.translationY)
        assertEquals(196.5f, v.translationX)
    }

    @Test fun rotationReclampsToNewGeometry() {
        val zoomed = VideoViewport.IDENTITY.zoomed(4f, 300f, 426f, portrait)
        val landscape = checkNotNull(VideoContentMapper.of(852f, 393f, 2560f, 1600f))
        val (cx, cy) = zoomed.clamped(landscape).toBase(0f, 0f, landscape)
        assertTrue(cx >= landscape.originX - 0.01f && cy >= landscape.originY - 0.01f)
    }

    @Test fun revealingScrollsTheCursorIntoView() {
        val zoomed = VideoViewport.IDENTITY.zoomed(4f, 196.5f, 426f, portrait).panned(10_000f, 0f, portrait)
        val target = portrait.originX + portrait.width * 0.9f
        val (vx, _) = zoomed.revealing(target, 426f, 24f, portrait).toView(target, 426f, portrait)
        assertTrue(vx >= 24f - 0.01f && vx <= 393f - 24f + 0.01f)
    }

    @Test fun trackpadMappingIgnoresPan() {
        val zoomed = VideoViewport.IDENTITY.zoomed(4f, 300f, 426f, portrait)
        val panned = zoomed.panned(-80f, 0f, portrait)
        assertNotEquals(zoomed, panned)
        assertTrue(near(zoomed.toBaseIgnoringPan(100f, 200f, portrait), panned.toBaseIgnoringPan(100f, 200f, portrait)))
    }

    @Test fun trackpadDeltasShrinkWithZoom() {
        val v = VideoViewport.IDENTITY.zoomed(4f, 196.5f, 426f, portrait)
        assertTrue(abs((v.toBase(200f, 426f, portrait).first - v.toBase(100f, 426f, portrait).first) - 25f) < 0.01f)
    }

    @Test fun invalidGeometryHasNoMapper() = assertNull(VideoContentMapper.of(0f, 852f, 2560f, 1600f))
}
