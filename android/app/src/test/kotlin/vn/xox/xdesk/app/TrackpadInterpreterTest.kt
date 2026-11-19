package vn.xox.xdesk.app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import vn.xox.xdesk.app.input.TouchPhase
import vn.xox.xdesk.app.input.TouchPhase.BEGAN
import vn.xox.xdesk.app.input.TouchPhase.CANCELLED
import vn.xox.xdesk.app.input.TouchPhase.ENDED
import vn.xox.xdesk.app.input.TouchPhase.MOVED
import vn.xox.xdesk.app.input.TouchSample
import vn.xox.xdesk.app.input.TrackpadConfig
import vn.xox.xdesk.app.input.TrackpadInterpreter
import vn.xox.xdesk.transport.InputButton
import vn.xox.xdesk.wire.InputEvent
import vn.xox.xdesk.wire.InputKind

class TrackpadInterpreterTest {
    private fun make(speed: Float = 1f, natural: Boolean = true, longPress: Boolean = true) =
        TrackpadInterpreter(TrackpadConfig(1000f, 500f, speed, natural, longPress))

    private fun TrackpadInterpreter.touch(id: Int, phase: TouchPhase, x: Float, y: Float, t: Long) = handle(TouchSample(id, x, y, phase, t))
    private fun kinds(events: List<InputEvent>) = events.map { it.kind }

    @Test
    fun tapClicksAtCursorNotAtFinger() {
        val t = make()
        assertTrue(t.touch(1, BEGAN, 0.9f, 0.9f, 0).isEmpty())
        val out = t.touch(1, ENDED, 0.9f, 0.9f, 80)
        assertEquals(listOf(InputKind.MOVE, InputKind.DOWN, InputKind.UP), kinds(out))
        assertEquals(0.5f, out[1].x); assertEquals(0.5f, out[1].y); assertEquals(InputButton.LEFT, out[1].button); assertEquals(1f, out[1].dx)
    }

    @Test
    fun jitterBelowSlopStaysATap() {
        val t = make()
        t.touch(1, BEGAN, 0.5f, 0.5f, 0)
        assertTrue(t.touch(1, MOVED, 0.51f, 0.5f, 16).isEmpty())
        assertEquals(listOf(InputKind.MOVE, InputKind.DOWN, InputKind.UP), kinds(t.touch(1, ENDED, 0.51f, 0.5f, 60)))
        assertEquals(0.5f, t.cursor.first)
    }

    @Test
    fun slowMoveIsRelativeWithLowGain() {
        val t = make()
        t.touch(1, BEGAN, 0.2f, 0.5f, 0)
        val out = t.touch(1, MOVED, 0.3f, 0.5f, 500)
        assertEquals(listOf(InputKind.MOVE), kinds(out))
        assertTrue(out[0].x > 0.5f && out[0].x < 0.6f)
        assertEquals(0.5f, out[0].y)
    }

    @Test
    fun fastMoveTravelsFartherThanSlow() {
        val slow = make(); val fast = make()
        slow.touch(1, BEGAN, 0.2f, 0.5f, 0); fast.touch(1, BEGAN, 0.2f, 0.5f, 0)
        slow.touch(1, MOVED, 0.3f, 0.5f, 1000); fast.touch(1, MOVED, 0.3f, 0.5f, 50)
        assertTrue(fast.cursor.first - 0.5f > 2 * (slow.cursor.first - 0.5f))
    }

    @Test
    fun speedSettingScalesTravel() {
        val normal = make(speed = 1f); val quick = make(speed = 2f)
        normal.touch(1, BEGAN, 0.2f, 0.5f, 0); quick.touch(1, BEGAN, 0.2f, 0.5f, 0)
        normal.touch(1, MOVED, 0.3f, 0.5f, 400); quick.touch(1, MOVED, 0.3f, 0.5f, 400)
        assertEquals(2 * (normal.cursor.first - 0.5f), quick.cursor.first - 0.5f, 0.001f)
    }

    @Test
    fun cursorIsClampedToDisplay() {
        val t = make()
        t.touch(1, BEGAN, 0.1f, 0.5f, 0)
        var time = 0L
        var x = 0.2f
        while (x < 3f) { time += 20; t.touch(1, MOVED, x, -2f, time); x += 0.2f }
        assertEquals(1f, t.cursor.first); assertEquals(0f, t.cursor.second)
        assertTrue(t.touch(1, MOVED, 3.2f, -2.2f, time + 20).isEmpty(), "đã chạm mép thì không gửi thêm move")
    }

    @Test
    fun movingFingerDoesNotClickOnRelease() {
        val t = make()
        t.touch(1, BEGAN, 0.2f, 0.5f, 0); t.touch(1, MOVED, 0.4f, 0.5f, 100)
        assertTrue(t.touch(1, ENDED, 0.4f, 0.5f, 150).isEmpty())
    }

    @Test
    fun longPressIsRightClickAtCursorAndCanBeDisabled() {
        val t = make()
        t.touch(1, BEGAN, 0.2f, 0.2f, 0)
        assertTrue(t.tick(499).isEmpty())
        val out = t.tick(500)
        assertEquals(listOf(InputKind.MOVE, InputKind.DOWN, InputKind.UP), kinds(out))
        assertEquals(InputButton.RIGHT, out[1].button); assertEquals(0.5f, out[1].x)
        assertTrue(t.touch(1, ENDED, 0.2f, 0.2f, 900).isEmpty())

        val off = make(longPress = false)
        off.touch(1, BEGAN, 0.2f, 0.2f, 0)
        assertTrue(off.tick(2000).isEmpty())
    }

    @Test
    fun twoFingerTapIsRightClickButSlowOneIsNot() {
        val t = make()
        t.touch(1, BEGAN, 0.4f, 0.5f, 0); t.touch(2, BEGAN, 0.5f, 0.5f, 10)
        val out = t.touch(2, ENDED, 0.5f, 0.5f, 100)
        assertEquals(InputButton.RIGHT, out[1].button)
        assertTrue(t.touch(1, ENDED, 0.4f, 0.5f, 110).isEmpty())

        val slow = make()
        slow.touch(1, BEGAN, 0.4f, 0.5f, 0); slow.touch(2, BEGAN, 0.5f, 0.5f, 10)
        assertTrue(slow.touch(2, ENDED, 0.5f, 0.5f, 600).isEmpty())
    }

    @Test
    fun twoFingerDragScrollsNaturalAndReversed() {
        val natural = make(); val reversed = make(natural = false)
        for (t in listOf(natural, reversed)) { t.touch(1, BEGAN, 0.4f, 0.5f, 1); t.touch(2, BEGAN, 0.6f, 0.5f, 2) }
        val a = natural.touch(1, MOVED, 0.4f, 0.6f, 50)
        val b = reversed.touch(1, MOVED, 0.4f, 0.6f, 50)
        assertEquals(listOf(InputKind.SCROLL), kinds(a))
        assertTrue(a[0].dy > 0f && b[0].dy < 0f)
        assertEquals(a[0].dy, -b[0].dy, 0.001f)
        assertEquals(0.5f, natural.cursor.first, "cuộn không dời con trỏ")
    }

    @Test
    fun tapThenTouchAndMoveDragsWithButtonDown() {
        val t = make()
        t.touch(1, BEGAN, 0.3f, 0.3f, 0); t.touch(1, ENDED, 0.3f, 0.3f, 50)
        assertTrue(t.touch(2, BEGAN, 0.6f, 0.6f, 150).isEmpty())
        val drag = t.touch(2, MOVED, 0.7f, 0.6f, 250)
        assertEquals(listOf(InputKind.MOVE, InputKind.DOWN, InputKind.MOVE), kinds(drag))
        assertEquals(InputButton.LEFT, drag[1].button)
        assertEquals(listOf(InputKind.MOVE), kinds(t.touch(2, MOVED, 0.75f, 0.6f, 300)))
        assertEquals(listOf(InputKind.UP), kinds(t.touch(2, ENDED, 0.75f, 0.6f, 400)))
    }

    @Test
    fun tapThenTapIsDoubleClickAndLateSecondTapIsSingle() {
        val t = make()
        t.touch(1, BEGAN, 0.3f, 0.3f, 0); t.touch(1, ENDED, 0.3f, 0.3f, 50)
        t.touch(2, BEGAN, 0.3f, 0.3f, 150)
        assertEquals(2f, t.touch(2, ENDED, 0.3f, 0.3f, 200)[1].dx)
        t.touch(3, BEGAN, 0.3f, 0.3f, 1000)
        assertEquals(1f, t.touch(3, ENDED, 0.3f, 0.3f, 1050)[1].dx)
    }

    @Test
    fun secondFingerOrCancelDuringDragReleasesButton() {
        val t = make()
        t.touch(1, BEGAN, 0.3f, 0.3f, 0); t.touch(1, ENDED, 0.3f, 0.3f, 50)
        t.touch(2, BEGAN, 0.5f, 0.5f, 100); t.touch(2, MOVED, 0.6f, 0.5f, 150)
        assertEquals(listOf(InputKind.UP), kinds(t.touch(3, BEGAN, 0.2f, 0.2f, 200)))

        val c = make()
        c.touch(1, BEGAN, 0.3f, 0.3f, 0); c.touch(1, ENDED, 0.3f, 0.3f, 50)
        c.touch(2, BEGAN, 0.5f, 0.5f, 100); c.touch(2, MOVED, 0.6f, 0.5f, 150)
        assertEquals(listOf(InputKind.UP), kinds(c.touch(2, CANCELLED, 0.6f, 0.5f, 200)))
    }

    @Test
    fun cursorSurvivesAcrossGestures() {
        val t = make()
        t.touch(1, BEGAN, 0.2f, 0.5f, 0); t.touch(1, MOVED, 0.3f, 0.5f, 400); t.touch(1, ENDED, 0.3f, 0.5f, 450)
        val moved = t.cursor.first
        t.touch(2, BEGAN, 0.9f, 0.1f, 2000)
        assertEquals(moved, t.touch(2, ENDED, 0.9f, 0.1f, 2050)[1].x)
    }
}
