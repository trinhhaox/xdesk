package vn.xox.xdesk.app.input

/**
 * Zoom + kéo (pan) của video trong view, dùng ở kiểu Bản sao "Giống màn hình Mac": cả màn hình Mac letterbox vừa khung, người dùng
 * phóng to để chạm vào chi tiết nhỏ. Điểm `base` (video chưa zoom) ↔ điểm trong view: `view = c + zoom * (base - c) + t`, `c` là tâm view.
 * Zoom 1 = vừa khung; không bao giờ kéo hở mép video. Cổng của `VideoViewport` bên Swift.
 */
data class VideoViewport(val zoom: Float = 1f, val translationX: Float = 0f, val translationY: Float = 0f) {
    val isIdentity: Boolean get() = this == IDENTITY

    /** Điểm trong view → điểm video chưa zoom (toạ độ đưa cho [VideoContentMapper]). */
    fun toBase(x: Float, y: Float, m: VideoContentMapper): Pair<Float, Float> {
        val cx = m.viewWidth / 2
        val cy = m.viewHeight / 2
        return (cx + (x - cx - translationX) / zoom) to (cy + (y - cy - translationY) / zoom)
    }

    /** Như [toBase] nhưng bỏ độ kéo: cho trackpad (chỉ cần độ dời), con trỏ chạy ra mép làm video tự kéo cũng không tính thành trượt. */
    fun toBaseIgnoringPan(x: Float, y: Float, m: VideoContentMapper): Pair<Float, Float> {
        val cx = m.viewWidth / 2
        val cy = m.viewHeight / 2
        return (cx + (x - cx) / zoom) to (cy + (y - cy) / zoom)
    }

    /** Điểm video chưa zoom → điểm trong view. */
    fun toView(x: Float, y: Float, m: VideoContentMapper): Pair<Float, Float> {
        val cx = m.viewWidth / 2
        val cy = m.viewHeight / 2
        return (cx + zoom * (x - cx) + translationX) to (cy + zoom * (y - cy) + translationY)
    }

    /** Nhân zoom với [factor] (tối đa [MAX_ZOOM]), giữ điểm video đang dưới [focus] (toạ độ view) đứng yên. */
    fun zoomed(factor: Float, focusX: Float, focusY: Float, m: VideoContentMapper): VideoViewport {
        if (!(factor.isFinite() && factor > 0f && focusX.isFinite() && focusY.isFinite())) return this
        val (bx, by) = toBase(focusX, focusY, m)
        val z = (zoom * factor).coerceIn(1f, MAX_ZOOM)
        val cx = m.viewWidth / 2
        val cy = m.viewHeight / 2
        return VideoViewport(z, focusX - cx - z * (bx - cx), focusY - cy - z * (by - cy)).clamped(m)
    }

    fun panned(dx: Float, dy: Float, m: VideoContentMapper): VideoViewport =
        if (dx.isFinite() && dy.isFinite()) copy(translationX = translationX + dx, translationY = translationY + dy).clamped(m) else this

    /** Kéo vừa đủ để điểm video [base] nằm trong view, cách mép ít nhất [margin] (con trỏ trackpad chạy ra mép khi đang zoom). */
    fun revealing(baseX: Float, baseY: Float, margin: Float, m: VideoContentMapper): VideoViewport {
        val (px, py) = toView(baseX, baseY, m)
        if (!(px.isFinite() && py.isFinite())) return this
        val dx = shift(px, m.viewWidth, margin)
        val dy = shift(py, m.viewHeight, margin)
        return if (dx == 0f && dy == 0f) this else panned(dx, dy, m)
    }

    /** Ép lại sau khi kích thước view/video đổi (xoay máy): trục nào video đã nhỏ hơn view thì căn giữa. */
    fun clamped(m: VideoContentMapper): VideoViewport = copy(
        translationX = clampAxis(translationX, zoom, m.originX, m.originX + m.width, m.viewWidth),
        translationY = clampAxis(translationY, zoom, m.originY, m.originY + m.height, m.viewHeight),
    )

    private fun shift(value: Float, length: Float, margin: Float): Float {
        val safe = minOf(margin, length / 2)
        return when {
            value < safe -> safe - value
            value > length - safe -> length - safe - value
            else -> 0f
        }
    }

    private fun clampAxis(t: Float, zoom: Float, lo: Float, hi: Float, length: Float): Float {
        val c = length / 2
        val scaledLo = c + zoom * (lo - c)
        val scaledHi = c + zoom * (hi - c)
        if (scaledHi - scaledLo <= length) return length / 2 - (scaledLo + scaledHi) / 2
        return t.coerceIn(length - scaledHi, -scaledLo)
    }

    companion object {
        const val MAX_ZOOM = 5f
        val IDENTITY = VideoViewport()
    }
}
