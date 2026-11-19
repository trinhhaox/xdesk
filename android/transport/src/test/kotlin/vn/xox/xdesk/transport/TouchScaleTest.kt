package vn.xox.xdesk.transport

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.ControlMessageCodec
import vn.xox.xdesk.wire.ControlEnvelope
import vn.xox.xdesk.wire.MirrorFit
import vn.xox.xdesk.wire.ScreenMode

class TouchScaleTest {
    @Test
    fun phoneIsLimitedByMinimumLogicalShortEdge() {
        assertEquals(393.0 / 540.0, TouchScale.magnification(393.0, 852.0), 1e-9)
        assertEquals(540.0 to 1171.0, TouchScale.logicalSize(393.0, 852.0))
        assertEquals(1171.0 to 540.0, TouchScale.logicalSize(852.0, 393.0))
    }

    @Test
    fun tabletAndLargeSurfaces() {
        assertEquals(820.0 / 540.0, TouchScale.magnification(820.0, 1180.0), 1e-9)
        assertEquals(2.0, TouchScale.magnification(1600.0, 2400.0))
        assertEquals(540.0, TouchScale.logicalSize(300.0, 500.0).first)
    }

    @Test
    fun touchConfigIsHiDPIAtLogicalSizeAndRoundTripsOnTheWire() {
        // Pixel 8 giả định: 1080×2400 px, density 2.75 → 393×873 dp.
        val config = checkNotNull(DisplayConfigPlanner.config(1080.0, 2400.0, 2.75, mode = ScreenMode.MIRROR, mirrorFit = MirrorFit.TOUCH))
        assertEquals(MirrorFit.TOUCH, config.fit)
        assertEquals(2.0, config.scale)
        assertEquals(2.0 * config.w / 2, config.w.toDouble())
        val bytes = ControlMessageCodec.encode(ControlEnvelope(1, config))
        assertEquals(config, ControlMessageCodec.decode(bytes).message)
    }

    @Test
    fun fitDeviceIsOmittedExtendIgnoresFitAndNativeSendsLongShortHint() {
        val fit = checkNotNull(DisplayConfigPlanner.config(1080.0, 2400.0, 2.75, mode = ScreenMode.MIRROR, mirrorFit = MirrorFit.FIT_DEVICE))
        assertNull(fit.mirrorFit)
        assertEquals(MirrorFit.FIT_DEVICE, fit.fit)
        assertEquals(1080L to 2400L, fit.w to fit.h)
        val extend = checkNotNull(DisplayConfigPlanner.config(1080.0, 2400.0, 2.75, mode = ScreenMode.EXTEND, mirrorFit = MirrorFit.TOUCH))
        assertNull(extend.mirrorFit)
        val native = checkNotNull(DisplayConfigPlanner.config(1080.0, 2400.0, 2.75, mode = ScreenMode.MIRROR, mirrorFit = MirrorFit.NATIVE))
        assertEquals(MirrorFit.NATIVE, native.mirrorFit)
        assertEquals(2400L to 1080L, native.w to native.h)
        val rotated = checkNotNull(DisplayConfigPlanner.config(2400.0, 1080.0, 2.75, mode = ScreenMode.MIRROR, mirrorFit = MirrorFit.NATIVE))
        assertEquals(native, rotated)
        assertNull(DisplayConfigPlanner.config(1080.0, 2400.0, 2.75, mode = ScreenMode.EXTEND, mirrorFit = MirrorFit.NATIVE)?.mirrorFit)
        assertTrue(extend is ControlMessage.DisplayConfig)
    }
}
