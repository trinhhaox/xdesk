package vn.xox.xdesk.app

import vn.xox.xdesk.transport.InputButton
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import vn.xox.xdesk.app.input.GestureConfig
import vn.xox.xdesk.app.input.GestureInterpreter
import vn.xox.xdesk.app.input.HidKeys
import vn.xox.xdesk.app.input.PointerAcceleration
import vn.xox.xdesk.app.input.PointerMode
import vn.xox.xdesk.app.input.PointerSettings
import vn.xox.xdesk.app.input.StickyModifiers
import vn.xox.xdesk.app.input.StickyModifiers.State
import vn.xox.xdesk.app.input.TouchPhase
import vn.xox.xdesk.app.input.TouchSample
import vn.xox.xdesk.app.input.VideoPan
import vn.xox.xdesk.app.input.createPointerGestures
import vn.xox.xdesk.transport.InputModifiers
import vn.xox.xdesk.wire.InputKind

class PointerLogicTest {
    @Test
    fun defaultsKeepDirectBehaviour() {
        val s = PointerSettings()
        assertTrue(s.mode == PointerMode.DIRECT && s.speed == 1f && s.naturalScroll && s.longPressRightClick)
    }

    @Test
    fun speedIsClampedAndNonFiniteFallsBack() {
        assertEquals(PointerSettings.SPEED_RANGE.endInclusive, PointerSettings(speed = 99f).safeSpeed)
        assertEquals(PointerSettings.SPEED_RANGE.start, PointerSettings(speed = 0f).safeSpeed)
        assertEquals(1f, PointerSettings(speed = Float.NaN).safeSpeed)
    }

    @Test
    fun accelerationCurveIsMonotonicAndCapped() {
        val gains = listOf(0f, 0.1f, 0.5f, 1f, 2f, 10f).map { PointerAcceleration.gain(it, 1f) }
        assertEquals(gains.sorted(), gains)
        assertEquals(PointerAcceleration.BASE_GAIN, gains.first())
        assertEquals(PointerAcceleration.MAX_GAIN, gains.last())
        assertEquals(PointerAcceleration.BASE_GAIN, PointerAcceleration.gain(-5f, 1f))
        assertEquals(PointerAcceleration.BASE_GAIN, PointerAcceleration.gain(Float.POSITIVE_INFINITY, 1f))
        assertEquals(2 * PointerAcceleration.gain(0.4f, 1f), PointerAcceleration.gain(0.4f, 2f), 1e-6f)
    }

    @Test
    fun factoryPicksTrackpadOnlyWhenAsked() {
        val direct = createPointerGestures(PointerSettings(), 1000f, 500f)
        val pad = createPointerGestures(PointerSettings(mode = PointerMode.TRACKPAD), 1000f, 500f, 0.25f to 0.75f)
        assertNull(direct.cursor)
        assertEquals(0.25f to 0.75f, pad.cursor)
        val begin = TouchSample(1, 0.9f, 0.9f, TouchPhase.BEGAN, 0)
        val end = TouchSample(1, 0.9f, 0.9f, TouchPhase.ENDED, 50)
        direct.handle(begin); pad.handle(begin)
        assertEquals(0.9f, direct.handle(end)[1].x, "trực tiếp: click tại ngón")
        assertEquals(0.25f, pad.handle(end)[1].x, "trackpad: click tại con trỏ")
    }

    @Test
    fun directModeHonoursLongPressAndNaturalScrollSettings() {
        val off = createPointerGestures(PointerSettings(longPressRightClick = false), 1000f, 500f)
        off.handle(TouchSample(1, 0.5f, 0.5f, TouchPhase.BEGAN, 0))
        off.tick(5000)
        val release = off.handle(TouchSample(1, 0.5f, 0.5f, TouchPhase.ENDED, 5050))
        assertEquals(InputButton.LEFT, release.first().button, "tắt nhấn giữ = chuột phải: nhả ra là click trái")

        val reversed = GestureInterpreter(GestureConfig(1000f, 500f, naturalScroll = false))
        reversed.handle(TouchSample(1, 0.4f, 0.5f, TouchPhase.BEGAN, 0)); reversed.handle(TouchSample(2, 0.6f, 0.5f, TouchPhase.BEGAN, 1))
        val out = reversed.handle(TouchSample(1, 0.4f, 0.6f, TouchPhase.MOVED, 20))
        assertEquals(InputKind.SCROLL, out.first().kind)
        assertTrue(out.first().dy < 0f)
    }

    @Test
    fun singleTapArmsForOneKeyThenReleases() {
        val armed = StickyModifiers().tap(InputModifiers.COMMAND, 0)
        assertEquals(State.ARMED, armed.state(InputModifiers.COMMAND))
        val (mods, after) = armed.consume()
        assertEquals(InputModifiers.COMMAND, mods)
        assertEquals(0, after.active)
    }

    @Test
    fun doubleTapLocksAndSurvivesConsume() {
        val locked = StickyModifiers().tap(InputModifiers.SHIFT, 0).tap(InputModifiers.SHIFT, 200)
        assertEquals(State.LOCKED, locked.state(InputModifiers.SHIFT))
        val (first, afterFirst) = locked.consume()
        assertEquals(InputModifiers.SHIFT, first)
        assertEquals(InputModifiers.SHIFT, afterFirst.consume().first)
        assertEquals(State.OFF, afterFirst.tap(InputModifiers.SHIFT, 5000).state(InputModifiers.SHIFT))
    }

    @Test
    fun slowSecondTapOrInterleavedModifierDoesNotLock() {
        assertEquals(State.OFF, StickyModifiers().tap(InputModifiers.OPTION, 0).tap(InputModifiers.OPTION, 2000).state(InputModifiers.OPTION))
        val interleaved = StickyModifiers().tap(InputModifiers.COMMAND, 0).tap(InputModifiers.SHIFT, 50).tap(InputModifiers.COMMAND, 100)
        assertEquals(State.OFF, interleaved.state(InputModifiers.COMMAND))
    }

    @Test
    fun modifiersCombine() {
        val both = StickyModifiers().tap(InputModifiers.COMMAND, 0).tap(InputModifiers.SHIFT, 100)
        assertEquals(InputModifiers.COMMAND or InputModifiers.SHIFT, both.active)
    }

    @Test
    fun videoPanOnlyAsMuchAsNeededAndClamped() {
        assertEquals(0f, VideoPan.offset(100f, 400f, 200f, 400f))
        assertEquals(78f, VideoPan.offset(250f, 400f, 200f, 400f))
        assertEquals(200f, VideoPan.offset(399f, 400f, 200f, 400f))
        assertEquals(30f, VideoPan.offset(390f, 600f, 300f, 330f), "dừng ở đáy video")
        assertEquals(0f, VideoPan.offset(Float.NaN, 400f, 200f, 400f))
        assertEquals(0f, VideoPan.offset(300f, 400f, 0f, 400f))
    }

    @Test
    fun charactersMapToHidOnlyWhenNoShiftNeeded() {
        assertEquals(0x06, HidKeys.fromChar('c'))
        assertEquals(0x1E, HidKeys.fromChar('1'))
        assertEquals(0x27, HidKeys.fromChar('0'))
        assertEquals(HidKeys.SPACE, HidKeys.fromChar(' '))
        assertNull(HidKeys.fromChar('ế')); assertNull(HidKeys.fromChar('C')); assertNull(HidKeys.fromChar('!'))
    }
}
