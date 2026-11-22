package vn.xox.xdesk.app.input

/** Ô phím đã đặt chỗ, đơn vị dp, gốc là góc trái trên của vùng bàn phím. */
data class KeyRect(val key: MacKey, val row: Int, val x: Float, val y: Float, val width: Float, val height: Float) {
    val right: Float get() = x + width
    val bottom: Float get() = y + height
}

data class KeyboardGeometry(
    val rects: List<KeyRect>,
    val showFunctionRow: Boolean,
    /** Bật lớp fn (hàng số thành esc/F1–F12); chỉ có nghĩa khi không có hàng F. */
    val fnLayer: Boolean,
    /** Chiều cao nhìn thấy của phím thường (không tính hàng F và phím mũi tên nửa chiều). */
    val keyHeight: Float,
    /** false nếu vùng quá thấp để đạt chiều cao tối thiểu (đã ẩn hàng F mà vẫn thiếu). */
    val fits: Boolean,
)

data class KeyboardSplit(val trackpadHeight: Float, val keyboardHeight: Float)

/** Tính bố cục bàn phím thuần (không Compose) từ kích thước thật còn lại, để kiểm thử và để không phím nào chồng nhau. */
object KeyboardGeometryCalculator {
    const val GAP = 4f
    const val MIN_KEY_HEIGHT_LANDSCAPE = 34f
    const val MIN_KEY_HEIGHT_PORTRAIT = 40f
    const val MAX_KEY_HEIGHT = 64f
    const val MIN_TRACKPAD_HEIGHT = 120f
    private const val KEYBOARD_SHARE = 0.6f

    fun minKeyHeight(landscape: Boolean) = if (landscape) MIN_KEY_HEIGHT_LANDSCAPE else MIN_KEY_HEIGHT_PORTRAIT

    /** Chiều cao tối thiểu để có đủ 6 hàng (cả hàng F) với phím đạt cỡ tối thiểu. */
    fun heightForFunctionRow(landscape: Boolean): Float =
        MacKeyLayout.rowHeightScales.sum() * (minKeyHeight(landscape) + GAP)

    /** [landscape] là hướng của màn hình (không suy ra từ khung bàn phím: dọc vẫn có khung rộng hơn cao) để chọn cỡ phím tối thiểu. */
    fun compute(width: Float, height: Float, landscape: Boolean, fnActive: Boolean = false): KeyboardGeometry {
        val minH = minKeyHeight(landscape)
        val withF = height / MacKeyLayout.rowHeightScales.sum() - GAP >= minH
        val scales = MacKeyLayout.rowHeightScalesFor(withF)
        val cell = minOf(height / scales.sum(), MAX_KEY_HEIGHT + GAP)
        val fnLayer = fnActive && !withF
        val rows = MacKeyLayout.rowsFor(withF, fnLayer)
        val unit = width / MacKeyLayout.ROW_UNITS
        var rowTop = (height - cell * scales.sum()) / 2
        val rects = ArrayList<KeyRect>()
        rows.forEachIndexed { r, row ->
            val rowH = cell * scales[r]
            var x = 0f
            var i = 0
            while (i < row.size) {
                val key = row[i]
                val w = key.width * unit - GAP
                if (key.halfHeight) {
                    val start = i
                    while (i < row.size && row[i].halfHeight) i++
                    val slot = rowH / (i - start)
                    for (j in start until i) {
                        rects += KeyRect(row[j], r, x + GAP / 2, rowTop + (j - start) * slot + GAP / 2, w, slot - GAP)
                    }
                } else {
                    rects += KeyRect(key, r, x + GAP / 2, rowTop + GAP / 2, w, rowH - GAP)
                    i++
                }
                x += key.width * unit
            }
            rowTop += rowH
        }
        val keyHeight = cell - GAP
        return KeyboardGeometry(rects, withF, fnLayer, keyHeight, fits = keyHeight >= minH)
    }

    /**
     * Dọc: vùng chuột trên, bàn phím dưới (~60%, không vượt cỡ phím tối đa). Thiếu chỗ cho hàng F thì vùng chuột co
     * lại trước (tối thiểu [MIN_TRACKPAD_HEIGHT]); hết chỗ nữa mới để [compute] ẩn hàng F.
     */
    fun portraitSplit(availableHeight: Float): KeyboardSplit {
        val maxUseful = MacKeyLayout.rowHeightScales.sum() * (MAX_KEY_HEIGHT + GAP)
        val roomForKeyboard = (availableHeight - MIN_TRACKPAD_HEIGHT).coerceAtLeast(0f)
        var keyboard = minOf(availableHeight * KEYBOARD_SHARE, maxUseful)
        val needed = heightForFunctionRow(landscape = false)
        if (keyboard < needed) keyboard = minOf(needed, roomForKeyboard)
        keyboard = keyboard.coerceIn(0f, availableHeight)
        return KeyboardSplit(trackpadHeight = availableHeight - keyboard, keyboardHeight = keyboard)
    }

    /** Cỡ chữ (sp) trên phím: ký tự đơn ≥ 13, nhãn dài co theo bề rộng/chiều cao ô nhưng không dưới 8. */
    fun labelFontSp(label: String, keyWidth: Float, keyHeight: Float): Float {
        if (label.length <= 1) return (keyHeight * 0.42f).coerceIn(13f, 20f)
        val lines = label.split('\n')
        val byWidth = (keyWidth - 6f) / (lines.maxOf { it.length } * 0.58f)
        val byHeight = (keyHeight - 6f) / (lines.size * 1.25f)
        return minOf(12f, byWidth, byHeight).coerceAtLeast(8f)
    }
}
