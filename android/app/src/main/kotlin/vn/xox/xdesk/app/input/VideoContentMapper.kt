package vn.xox.xdesk.app.input

/**
 * Đổi toạ độ trong view (gốc trên-trái, px) sang 0…1 trên khung video thật. Video luôn aspect-fit (letterbox) nên dải đen
 * hai bên không phải màn hình host. Cổng của `VideoContentMapper` bên Swift.
 */
class VideoContentMapper private constructor(val viewWidth: Float, val viewHeight: Float, contentWidth: Float, contentHeight: Float) {
    private val scale = minOf(viewWidth / contentWidth, viewHeight / contentHeight)
    val width = contentWidth * scale
    val height = contentHeight * scale
    val originX = (viewWidth - width) / 2
    val originY = (viewHeight - height) / 2

    /** `clamping` = false: chạm vào dải đen → null. `clamping` = true: ép vào mép khung (đang kéo ra ngoài). */
    fun normalize(x: Float, y: Float, clamping: Boolean = false): Pair<Float, Float>? {
        val nx = (x - originX) / width
        val ny = (y - originY) / height
        if (!nx.isFinite() || !ny.isFinite()) return null
        if (clamping) return nx.coerceIn(0f, 1f) to ny.coerceIn(0f, 1f)
        return if (nx in 0f..1f && ny in 0f..1f) nx to ny else null
    }

    /** Không ép vào khung: ngón trượt qua dải đen vẫn cho delta đúng (trackpad chỉ cần độ dời). */
    fun normalizeUnbounded(x: Float, y: Float): Pair<Float, Float> = (x - originX) / width to (y - originY) / height

    companion object {
        /** null khi kích thước view hoặc nội dung không hợp lệ (≤ 0, không hữu hạn). */
        fun of(viewWidth: Float, viewHeight: Float, contentWidth: Float, contentHeight: Float): VideoContentMapper? =
            if (listOf(viewWidth, viewHeight, contentWidth, contentHeight).all { it.isFinite() && it > 0f }) {
                VideoContentMapper(viewWidth, viewHeight, contentWidth, contentHeight)
            } else null
    }
}
