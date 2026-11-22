package vn.xox.xdesk.app.input

/** Một phím số: gửi HID keypad thật (không gửi văn bản) để Mac coi là bàn phím số. */
data class NumpadKey(val label: String, val usage: Int)

object NumpadLayout {
    private fun digitKey(c: Char) = NumpadKey(c.toString(), checkNotNull(HidKeys.keypadUsage(c)))

    /** Lưới 4 cột × 4 hàng: 7 8 9 / · 4 5 6 * · 1 2 3 - · 0 . = + */
    val rows: List<List<NumpadKey>> = listOf("789/", "456*", "123-", "0.=+").map { row -> row.map(::digitKey) }

    /** Hàng cuối chia đôi: xoá lùi và Enter của bàn phím số. */
    val bottomRow: List<NumpadKey> = listOf(NumpadKey("⌫", HidKeys.BACKSPACE), NumpadKey("↩", HidKeys.KEYPAD_ENTER))
}
