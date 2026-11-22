package vn.xox.xdesk.app

/** Tốc độ khung hình mục tiêu khi phát hình; luôn giới hạn theo tần số quét tối đa của màn hình thiết bị. */
enum class StreamQualityPreset(val targetFps: Int, val shortLabel: String) {
    SAVER_30(30, "30 fps"),
    STANDARD_60(60, "60 fps"),
    HIGH_120(120, "120 fps");

    fun effectiveFps(maxDeviceFps: Int): Int = minOf(targetFps, maxOf(30, maxDeviceFps))

    fun footer(maxDeviceFps: Int): String {
        val capped = effectiveFps(maxDeviceFps)
        return when (this) {
            SAVER_30 -> "Tiết kiệm pin và băng thông, phù hợp văn bản và công việc văn phòng."
            STANDARD_60 -> "Cân bằng độ mượt và thời lượng pin (mặc định)."
            HIGH_120 -> if (capped < 120) {
                "Ưu tiên mượt tối đa (tự giới hạn ở $capped fps theo màn hình thiết bị này)."
            } else {
                "Mượt tối đa 120 fps, tốn pin và băng thông hơn."
            }
        }
    }
}
