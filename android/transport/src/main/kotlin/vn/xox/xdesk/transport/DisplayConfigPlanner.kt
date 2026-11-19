package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.MirrorFit
import vn.xox.xdesk.wire.ScreenMode
import vn.xox.xdesk.wire.VideoCodec

/** Tính `display.config` từ kích thước màn hình viewer (px). Xoay màn hình = gọi lại với kích thước đã hoán đổi. */
object DisplayConfigPlanner {
    const val MAX_PIXELS = 16384.0
    const val MAX_SCALE = 8.0

    /**
     * `null` nếu đầu vào không hợp lệ. Cạnh làm tròn lên số chẵn (bộ mã hoá 4:2:0) và chặn ở giới hạn wire.
     * `mirrorFit` chỉ có nghĩa khi `mode == MIRROR`: FIT_DEVICE bị bỏ khỏi wire (mặc định); TOUCH gửi kích thước logic × 2 và scale 2
     * (xem [TouchScale]); NATIVE gửi (cạnh dài, cạnh ngắn) làm gợi ý để xoay máy không đổi cấu hình (host bỏ qua w/h, giữ nguyên Mac).
     */
    fun config(
        widthPx: Double, heightPx: Double, scale: Double, fps: Long = 60, codec: VideoCodec = VideoCodec.H264,
        mode: ScreenMode = ScreenMode.EXTEND, mirrorFit: MirrorFit = MirrorFit.FIT_DEVICE,
    ): ControlMessage.DisplayConfig? {
        if (!listOf(widthPx, heightPx, scale).all { it.isFinite() && it > 0 }) return null
        val wireMode = if (mode == ScreenMode.EXTEND) null else mode
        val fit = if (mode == ScreenMode.MIRROR) mirrorFit else MirrorFit.FIT_DEVICE
        val clamped = minOf(scale, MAX_SCALE)
        if (fit == MirrorFit.TOUCH) {
            val (lw, lh) = TouchScale.logicalSize(widthPx / scale, heightPx / scale)
            return ControlMessage.DisplayConfig(evenPixels(lw * 2), evenPixels(lh * 2), 2.0, fps, codec, wireMode, MirrorFit.TOUCH)
        }
        if (fit == MirrorFit.NATIVE) {
            return ControlMessage.DisplayConfig(evenPixels(maxOf(widthPx, heightPx)), evenPixels(minOf(widthPx, heightPx)), clamped, fps, codec, wireMode, MirrorFit.NATIVE)
        }
        return ControlMessage.DisplayConfig(evenPixels(widthPx), evenPixels(heightPx), clamped, fps, codec, wireMode)
    }

    private fun evenPixels(value: Double): Long = (Math.ceil(value / 2) * 2).coerceIn(2.0, MAX_PIXELS).toLong()
}
