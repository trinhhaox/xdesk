package vn.xox.xdesk.app.input

import vn.xox.xdesk.transport.InputModifiers

/** Một phím vật lý: `usage` là HID usage theo vị trí phím (Mac tự đổi sang chữ theo bộ gõ đang chọn). `width` tính theo đơn vị phím chuẩn. */
data class MacKey(
    val label: String,
    val usage: Int,
    val width: Float,
    val shifted: String? = null,
    val kind: Kind = Kind.NORMAL,
    /** Nửa chiều cao (↑ ↓ xếp chồng trong cụm mũi tên). */
    val halfHeight: Boolean = false,
) {
    enum class Kind { NORMAL, LETTER, MODIFIER, CAPS_LOCK, FN }

    /** Bit `mods` tương ứng nếu là phím bổ trợ, ngược lại 0. */
    val modifierBit: Int get() = MacKeyLayout.modifierBit(usage)
}

/** Bố cục Mac ANSI (nhãn tiếng Anh Mỹ) dưới dạng dữ liệu để kiểm thử; mọi hàng rộng đúng [ROW_UNITS] đơn vị. */
object MacKeyLayout {
    const val ROW_UNITS = 15f

    /** `fn` chỉ là phím lớp trên điện thoại (không gửi HID); usage giả để không trùng phím thật. */
    const val FN_USAGE = -1

    const val CAPS_LOCK = 0x39
    const val LEFT_CONTROL = 0xE0
    const val LEFT_SHIFT = 0xE1
    const val LEFT_OPTION = 0xE2
    const val LEFT_COMMAND = 0xE3
    const val RIGHT_SHIFT = 0xE5
    const val RIGHT_OPTION = 0xE6
    const val RIGHT_COMMAND = 0xE7

    /** Độ rộng hàng theo đơn vị phím; hai phím nửa chiều cao (↑ ↓) xếp chồng nên chỉ chiếm một cột. */
    fun rowUnits(row: List<MacKey>): Float {
        val full = row.filterNot { it.halfHeight }.sumOf { it.width.toDouble() }
        val stacked = row.filter { it.halfHeight }.sumOf { it.width.toDouble() } / 2
        return (full + stacked).toFloat()
    }

    fun isModifier(usage: Int): Boolean = usage in 0xE0..0xE7

    fun modifierBit(usage: Int): Int = when (usage) {
        LEFT_SHIFT, RIGHT_SHIFT -> InputModifiers.SHIFT
        LEFT_CONTROL, 0xE4 -> InputModifiers.CONTROL
        LEFT_OPTION, RIGHT_OPTION -> InputModifiers.OPTION
        LEFT_COMMAND, RIGHT_COMMAND -> InputModifiers.COMMAND
        else -> 0
    }

    private fun key(label: String, usage: Int, width: Float = 1f, shifted: String? = null) =
        MacKey(label, usage, width, shifted)

    private fun letter(c: Char) = MacKey(c.toString(), 0x04 + (c - 'a'), 1f, c.uppercase(), MacKey.Kind.LETTER)

    private fun mod(label: String, usage: Int, width: Float) = MacKey(label, usage, width, kind = MacKey.Kind.MODIFIER)

    private fun letters(chars: String) = chars.map(::letter)

    private val functionRow: List<MacKey> =
        listOf(key("esc", 0x29, 1.5f)) + (1..12).map { key("F$it", 0x3A + it - 1, 1.125f) }

    private val numberRow: List<MacKey> = listOf(
        key("`", 0x35, shifted = "~"), key("1", 0x1E, shifted = "!"), key("2", 0x1F, shifted = "@"),
        key("3", 0x20, shifted = "#"), key("4", 0x21, shifted = "$"), key("5", 0x22, shifted = "%"),
        key("6", 0x23, shifted = "^"), key("7", 0x24, shifted = "&"), key("8", 0x25, shifted = "*"),
        key("9", 0x26, shifted = "("), key("0", 0x27, shifted = ")"), key("-", 0x2D, shifted = "_"),
        key("=", 0x2E, shifted = "+"), key("delete ⌫", HidKeys.BACKSPACE, 2f),
    )

    private val topRow: List<MacKey> =
        listOf(key("tab", HidKeys.TAB, 1.5f)) + letters("qwertyuiop") +
            listOf(key("[", 0x2F, shifted = "{"), key("]", 0x30, shifted = "}"), key("\\", 0x31, 1.5f, "|"))

    private val homeRow: List<MacKey> =
        listOf(MacKey("caps lock", CAPS_LOCK, 1.75f, kind = MacKey.Kind.CAPS_LOCK)) + letters("asdfghjkl") +
            listOf(key(";", 0x33, shifted = ":"), key("'", 0x34, shifted = "\""), key("return", HidKeys.ENTER, 2.25f))

    private val bottomLetterRow: List<MacKey> =
        listOf(mod("shift", LEFT_SHIFT, 2.25f)) + letters("zxcvbnm") +
            listOf(key(",", 0x36, shifted = "<"), key(".", 0x37, shifted = ">"), key("/", 0x38, shifted = "?"), mod("shift", RIGHT_SHIFT, 2.75f))

    private val spaceRow: List<MacKey> = listOf(
        mod("⌃\ncontrol", LEFT_CONTROL, 1.25f), mod("⌥\noption", LEFT_OPTION, 1.25f), mod("⌘\ncommand", LEFT_COMMAND, 1.5f),
        key("", HidKeys.SPACE, 5.25f),
        mod("⌘\ncommand", RIGHT_COMMAND, 1.5f), mod("⌥\noption", RIGHT_OPTION, 1.25f),
        key("←", HidKeys.LEFT), MacKey("↑", HidKeys.UP, 1f, halfHeight = true), MacKey("↓", HidKeys.DOWN, 1f, halfHeight = true), key("→", HidKeys.RIGHT),
    )

    /** Lớp fn: esc + F1–F12 thay cho ` 1–0 - = khi đang bật fn ở bố cục thu gọn (không có hàng F). */
    private val fnNumberRow: List<MacKey> =
        listOf(key("esc", HidKeys.ESCAPE)) + (1..12).map { key("F$it", 0x3A + it - 1) } + key("delete ⌫", HidKeys.BACKSPACE, 2f)

    /** Hàng dưới thu gọn: thêm fn ở đầu, space co lại để tổng vẫn đủ [ROW_UNITS]. */
    private val compactSpaceRow: List<MacKey> = listOf(MacKey("fn", FN_USAGE, 1f, kind = MacKey.Kind.FN)) + spaceRow.map {
        if (it.usage == HidKeys.SPACE) it.copy(width = 4.25f) else it
    }

    private val compactRows: List<List<MacKey>> = listOf(numberRow, topRow, homeRow, bottomLetterRow, compactSpaceRow)

    /** Hệ số chiều cao từng hàng (hàng F thấp hơn). */
    val rowHeightScales: List<Float> = listOf(0.7f, 1f, 1f, 1f, 1f, 1f)

    val rows: List<List<MacKey>> = listOf(functionRow, numberRow, topRow, homeRow, bottomLetterRow, spaceRow)

    /** Bố cục theo chỗ có: đủ chỗ thì 6 hàng có hàng F; thiếu thì 5 hàng + fn (bật fn → hàng số thành esc/F1–F12). */
    fun rowsFor(showFunctionRow: Boolean, fnLayer: Boolean): List<List<MacKey>> = when {
        showFunctionRow -> rows
        fnLayer -> listOf(fnNumberRow) + compactRows.drop(1)
        else -> compactRows
    }

    fun rowHeightScalesFor(showFunctionRow: Boolean): List<Float> = if (showFunctionRow) rowHeightScales else List(compactRows.size) { 1f }

    /** Nhãn hiển thị: chữ cái hoa khi Shift và Caps Lock khác nhau (như Mac: Caps + Shift ra chữ thường); ký hiệu đổi khi Shift. */
    fun displayLabel(key: MacKey, shift: Boolean, caps: Boolean): String = when (key.kind) {
        MacKey.Kind.LETTER -> if (shift != caps) key.shifted ?: key.label else key.label
        else -> if (shift) key.shifted ?: key.label else key.label
    }
}
