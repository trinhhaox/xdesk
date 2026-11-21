package vn.xox.xdesk.media

import android.media.MediaFormat

internal object DecoderFormat {
    fun build(width: Int, height: Int, quirk: DecoderQuirk?, extraFormat: Map<String, Int>, mime: String = AndroidCodecList.MIME_AVC): MediaFormat =
        MediaFormat.createVideoFormat(mime, width, height).apply {
            setInteger(MediaFormat.KEY_LOW_LATENCY, 1) // gửi cả khi không quảng bá FEATURE_LowLatency: codec không biết thì bỏ qua
            setInteger(MediaFormat.KEY_PRIORITY, 0)
            setInteger(MediaFormat.KEY_OPERATING_RATE, Short.MAX_VALUE.toInt())
            quirk?.maxInputSizeBytes?.let { setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, it) }
            quirk?.lowLatencyKeys?.forEach { (k, value) -> setInteger(k, value) }
            extraFormat.forEach { (k, value) -> setInteger(k, value) }
        }

    /** Cỡ hiển thị thật của khung: codec có thể báo cỡ đã căn lề kèm các khoá crop. */
    fun visibleSize(format: MediaFormat, sizeKey: String, cropLow: String, cropHigh: String): Int {
        if (format.containsKey(cropLow) && format.containsKey(cropHigh)) return format.getInteger(cropHigh) - format.getInteger(cropLow) + 1
        return if (format.containsKey(sizeKey)) format.getInteger(sizeKey) else 0
    }
}
