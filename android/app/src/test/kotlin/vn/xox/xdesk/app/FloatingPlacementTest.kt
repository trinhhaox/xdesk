package vn.xox.xdesk.app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class FloatingPlacementTest {
    @Test fun trailingMenuOpensLeftOfButtonAndStaysOnScreen() {
        val (x, y) = FloatingPlacement(trailing = true).menuOrigin(668f, 900f, 96f, 480f, 600f, 8f, 720f, 1600f)
        assertEquals(180f, x)
        assertEquals(900f, y)
    }

    @Test fun menuNeverOverflowsASmallContainerAboveTheKeyboard() {
        val (x, y) = FloatingPlacement(trailing = false).menuOrigin(4f, 700f, 96f, 480f, 500f, 8f, 720f, 400f)
        assertTrue(x >= 0f && x + 480f <= 720f)
        assertEquals(8f, y)
    }

    @Test fun narrowContainerPinsMenuToLeftEdge() {
        val (x, _) = FloatingPlacement(trailing = true).menuOrigin(300f, 100f, 96f, 480f, 200f, 8f, 400f, 800f)
        assertEquals(0f, x)
    }
}
