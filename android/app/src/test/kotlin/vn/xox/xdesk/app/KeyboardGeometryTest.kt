package vn.xox.xdesk.app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import vn.xox.xdesk.app.input.HidKeys
import vn.xox.xdesk.app.input.KeyRect
import vn.xox.xdesk.app.input.KeyboardGeometry
import vn.xox.xdesk.app.input.KeyboardGeometryCalculator as Calc
import vn.xox.xdesk.app.input.MacKey
import vn.xox.xdesk.app.input.MacKeyLayout
import vn.xox.xdesk.app.input.NumpadLayout

class KeyboardGeometryTest {
    private val eps = 0.01f

    private fun overlaps(a: KeyRect, b: KeyRect) =
        a.x < b.right - eps && b.x < a.right - eps && a.y < b.bottom - eps && b.y < a.bottom - eps

    private fun assertSound(g: KeyboardGeometry, width: Float, height: Float, label: String) {
        g.rects.forEach {
            assertTrue(it.x >= -eps && it.y >= -eps && it.right <= width + eps && it.bottom <= height + eps, "$label: ${it.key.label} out of bounds")
            assertTrue(it.width > 0f && it.height > 0f, "$label: ${it.key.label} empty")
        }
        for (i in g.rects.indices) for (j in i + 1 until g.rects.size) {
            assertFalse(overlaps(g.rects[i], g.rects[j]), "$label: ${g.rects[i].key.label} overlaps ${g.rects[j].key.label}")
        }
    }

    private fun assertMinHeights(g: KeyboardGeometry, minH: Float, label: String) {
        g.rects.filter { !it.key.halfHeight && !(g.showFunctionRow && it.row == 0) }
            .forEach { assertTrue(it.height >= minH - eps, "$label: ${it.key.label} height ${it.height} < $minH") }
        g.rects.filter { it.key.halfHeight }.forEach { assertTrue(it.height >= 14f, "$label: arrow ${it.key.label} too short ${it.height}") }
        if (g.showFunctionRow) g.rects.filter { it.row == 0 }.forEach { assertTrue(it.height >= 0.7f * (minH + Calc.GAP) - Calc.GAP - eps, "$label: F row too short") }
    }

    @Test
    fun landscapePhonesShowFullKeyboardWithoutOverlapOnRemainingHeight() {
        // 800x360 và 667x375 trừ thanh trên ngang 36 dp.
        listOf(800f to 360f, 667f to 375f).forEach { (w, h) ->
            val area = h - 36f
            val g = Calc.compute(w, area, landscape = true)
            val label = "${w.toInt()}x${h.toInt()}"
            assertTrue(g.showFunctionRow, "$label shows F row")
            assertFalse(g.fnLayer)
            assertTrue(g.fits, label)
            assertEquals(6, g.rects.map { it.row }.toSet().size, label)
            assertSound(g, w, area, label)
            assertMinHeights(g, Calc.MIN_KEY_HEIGHT_LANDSCAPE, label)
        }
    }

    @Test
    fun portraitPhonesSplitTrackpadAndFullKeyboard() {
        // 360x800 và 375x667 trừ thanh trên dọc 48 dp.
        listOf(360f to 800f, 375f to 667f).forEach { (w, h) ->
            val area = h - 48f
            val split = Calc.portraitSplit(area)
            val label = "${w.toInt()}x${h.toInt()}"
            assertEquals(area, split.trackpadHeight + split.keyboardHeight, eps, label)
            assertTrue(split.trackpadHeight >= Calc.MIN_TRACKPAD_HEIGHT, label)
            val g = Calc.compute(w, split.keyboardHeight, landscape = false)
            assertTrue(g.showFunctionRow, label)
            assertTrue(g.fits, label)
            assertSound(g, w, split.keyboardHeight, label)
            assertMinHeights(g, Calc.MIN_KEY_HEIGHT_PORTRAIT, label)
        }
    }

    @Test
    fun portraitTrackpadShrinksBeforeFunctionRowIsHidden() {
        val needed = Calc.heightForFunctionRow(landscape = false)
        val area = needed + Calc.MIN_TRACKPAD_HEIGHT + 5f
        val split = Calc.portraitSplit(area)
        assertEquals(needed, split.keyboardHeight, eps)
        assertTrue(Calc.compute(360f, split.keyboardHeight, landscape = false).showFunctionRow)
        val tight = Calc.portraitSplit(Calc.MIN_TRACKPAD_HEIGHT + 225f)
        assertEquals(Calc.MIN_TRACKPAD_HEIGHT, tight.trackpadHeight, eps)
        assertFalse(Calc.compute(360f, tight.keyboardHeight, landscape = false).showFunctionRow)
    }

    @Test
    fun shortLandscapeHidesFunctionRowAndUsesFnLayer() {
        val (w, h) = 640f to 200f
        val plain = Calc.compute(w, h, landscape = true)
        assertFalse(plain.showFunctionRow)
        assertFalse(plain.fnLayer)
        assertEquals(5, plain.rects.map { it.row }.toSet().size)
        assertTrue(plain.fits)
        assertSound(plain, w, h, "plain")
        assertMinHeights(plain, Calc.MIN_KEY_HEIGHT_LANDSCAPE, "plain")
        val fn = Calc.compute(w, h, landscape = true, fnActive = true)
        assertTrue(fn.fnLayer)
        assertSound(fn, w, h, "fn")
        val firstRow = fn.rects.filter { it.row == 0 }.map { it.key.label }
        assertEquals(listOf("esc") + (1..12).map { "F$it" } + "delete ⌫", firstRow)
        assertNotNull(fn.rects.firstOrNull { it.key.kind == MacKey.Kind.FN })
    }

    @Test
    fun fnLayerIgnoredWhenFunctionRowFits() {
        val g = Calc.compute(800f, 324f, landscape = true, fnActive = true)
        assertTrue(g.showFunctionRow)
        assertFalse(g.fnLayer)
        assertEquals(0, g.rects.count { it.key.kind == MacKey.Kind.FN })
    }

    @Test
    fun everyLayoutRowIsFullWidthAndRowsAreAligned() {
        listOf(true, false).forEach { showF ->
            listOf(true, false).forEach { fn ->
                MacKeyLayout.rowsFor(showF, fn).forEachIndexed { i, row ->
                    assertEquals(MacKeyLayout.ROW_UNITS, MacKeyLayout.rowUnits(row), 0.001f, "showF=$showF fn=$fn row $i")
                }
            }
        }
        val compactBottom = MacKeyLayout.rowsFor(false, false).last()
        assertEquals(listOf("fn", "⌃\ncontrol", "⌥\noption", "⌘\ncommand"), compactBottom.take(4).map { it.label })
        assertEquals(listOf(1f, 1.25f, 1.25f, 1.5f), compactBottom.take(4).map { it.width })
        val g = Calc.compute(800f, 324f, landscape = true)
        val rightEdges = g.rects.filter { !it.key.halfHeight && it.row in 1..2 }.groupBy { it.row }.mapValues { (_, v) -> v.maxOf { it.right } }
        assertEquals(rightEdges[1]!!, rightEdges[2]!!, eps)
    }

    @Test
    fun labelFontsMeetMinimums() {
        assertTrue(Calc.labelFontSp("a", 20f, 40f) >= 13f)
        assertTrue(Calc.labelFontSp("a", 52f, 34f) >= 13f)
        assertTrue(Calc.labelFontSp("F10", 40f, 22f) >= 8f)
        assertTrue(Calc.labelFontSp("⌃\ncontrol", 70f, 34f) <= 12f)
    }

    @Test
    fun numpadSendsRealKeypadUsages() {
        val byLabel = (NumpadLayout.rows.flatten() + NumpadLayout.bottomRow).associate { it.label to it.usage }
        assertEquals(mapOf(
            "7" to 0x5F, "8" to 0x60, "9" to 0x61, "/" to 0x54,
            "4" to 0x5C, "5" to 0x5D, "6" to 0x5E, "*" to 0x55,
            "1" to 0x59, "2" to 0x5A, "3" to 0x5B, "-" to 0x56,
            "0" to 0x62, "." to 0x63, "=" to 0x67, "+" to 0x57,
            "⌫" to HidKeys.BACKSPACE, "↩" to 0x58,
        ), byLabel)
        assertEquals(4, NumpadLayout.rows.size)
        assertTrue(NumpadLayout.rows.all { it.size == 4 })
    }
}
