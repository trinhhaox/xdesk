package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.ScreenMode
import vn.xox.xdesk.wire.VideoCodec

/** Tính `display.config` từ kích thước màn hình viewer (px). Xoay màn hình = gọi lại với kích thước đã hoán đổi. */
object DisplayConfigPlanner {
    const val MAX_PIXELS = 16384.0
    const val MAX_SCALE = 8.0

    /** `null` nếu đầu vào không hợp lệ. Cạnh làm tròn lên số chẵn (bộ mã hoá 4:2:0) và chặn ở giới hạn wire. */
    fun config(
        widthPx: Double, heightPx: Double, scale: Double, fps: Long = 60, codec: VideoCodec = VideoCodec.H264,
        mode: ScreenMode = ScreenMode.EXTEND,
    ): ControlMessage.DisplayConfig? {
        if (!listOf(widthPx, heightPx, scale).all { it.isFinite() && it > 0 }) return null
        return ControlMessage.DisplayConfig(
            evenPixels(widthPx), evenPixels(heightPx), minOf(scale, MAX_SCALE), fps, codec,
            if (mode == ScreenMode.EXTEND) null else mode,
        )
    }

    private fun evenPixels(value: Double): Long = (Math.ceil(value / 2) * 2).coerceIn(2.0, MAX_PIXELS).toLong()
}
