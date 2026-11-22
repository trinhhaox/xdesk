package vn.xox.xdesk.app

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import vn.xox.xdesk.app.input.MacKey
import vn.xox.xdesk.app.input.MacKeyLayout
import vn.xox.xdesk.transport.InputModifiers

class MacKeyLayoutTest {
    private val all = MacKeyLayout.rows.flatten()

    @Test
    fun hasSixRowsEachExactlyFullWidth() {
        assertEquals(6, MacKeyLayout.rows.size)
        MacKeyLayout.rows.forEachIndexed { i, row -> assertEquals(MacKeyLayout.ROW_UNITS, MacKeyLayout.rowUnits(row), 0.001f, "row $i") }
    }

    @Test
    fun arrowClusterStacksUpAndDownAtHalfHeight() {
        assertEquals(listOf(0x52, 0x51), all.filter { it.halfHeight }.map { it.usage })
        assertEquals(6, MacKeyLayout.rowHeightScales.size)
        assertTrue(MacKeyLayout.rowHeightScales[0] < 1f)
    }

    @Test
    fun usagesAreValidAndUnique() {
        assertTrue(all.all { it.usage in 0x04..0x52 || it.usage in 0xE0..0xE7 })
        assertEquals(all.size, all.map { it.usage }.toSet().size)
        assertEquals(13 + 14 + 14 + 13 + 12 + 10, all.size)
    }

    @Test
    fun keyUsagesMatchPhysicalPositions() {
        fun usage(label: String) = all.first { it.label == label }.usage
        assertEquals(0x04, usage("a"))
        assertEquals(0x1D, usage("z"))
        assertEquals(0x1E, usage("1"))
        assertEquals(0x27, usage("0"))
        assertEquals(0x35, usage("`"))
        assertEquals(0x29, usage("esc"))
        assertEquals(0x3A, usage("F1"))
        assertEquals(0x45, usage("F12"))
        assertEquals(0x2A, usage("delete ⌫"))
        assertEquals(0x28, usage("return"))
        assertEquals(0x39, usage("caps lock"))
        assertEquals(0x2C, all.first { it.width == 5.25f }.usage)
    }

    @Test
    fun modifiersMapToBits() {
        assertEquals(InputModifiers.SHIFT, MacKeyLayout.modifierBit(MacKeyLayout.LEFT_SHIFT))
        assertEquals(InputModifiers.SHIFT, MacKeyLayout.modifierBit(MacKeyLayout.RIGHT_SHIFT))
        assertEquals(InputModifiers.CONTROL, MacKeyLayout.modifierBit(MacKeyLayout.LEFT_CONTROL))
        assertEquals(InputModifiers.OPTION, MacKeyLayout.modifierBit(MacKeyLayout.RIGHT_OPTION))
        assertEquals(InputModifiers.COMMAND, MacKeyLayout.modifierBit(MacKeyLayout.LEFT_COMMAND))
        assertEquals(0, MacKeyLayout.modifierBit(0x04))
        val mods = all.filter { it.kind == MacKey.Kind.MODIFIER }
        assertEquals(7, mods.size)
        assertTrue(mods.all { it.modifierBit != 0 })
    }

    @Test
    fun shiftedLabelsFollowShiftAndCaps() {
        fun key(label: String) = all.first { it.label == label }
        assertEquals("q", MacKeyLayout.displayLabel(key("q"), shift = false, caps = false))
        assertEquals("Q", MacKeyLayout.displayLabel(key("q"), shift = true, caps = false))
        assertEquals("Q", MacKeyLayout.displayLabel(key("q"), shift = false, caps = true))
        assertEquals("q", MacKeyLayout.displayLabel(key("q"), shift = true, caps = true))
        assertEquals("1", MacKeyLayout.displayLabel(key("1"), shift = false, caps = true))
        val pairs = mapOf("1" to "!", "2" to "@", "3" to "#", "4" to "$", "5" to "%", "6" to "^", "7" to "&", "8" to "*", "9" to "(", "0" to ")",
            "-" to "_", "=" to "+", "[" to "{", "]" to "}", "\\" to "|", ";" to ":", "'" to "\"", "," to "<", "." to ">", "/" to "?", "`" to "~")
        pairs.forEach { (base, shifted) -> assertEquals(shifted, MacKeyLayout.displayLabel(key(base), shift = true, caps = false), base) }
        assertEquals("tab", MacKeyLayout.displayLabel(key("tab"), shift = true, caps = false))
    }
}
