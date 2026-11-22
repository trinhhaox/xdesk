package vn.xox.xdesk.wire

/** Phiên bản giao thức `major.minor`. Major lệch → `reject{reason:"version"}`. */
data class ProtocolVersion(val major: Int, val minor: Int) {
    val string: String get() = "$major.$minor"

    fun isCompatibleWith(other: ProtocolVersion): Boolean = major == other.major

    companion object {
        val CURRENT = ProtocolVersion(1, 0)

        /** Phân tích "1.0"; `null` nếu sai định dạng. */
        fun parse(text: String): ProtocolVersion? {
            val parts = text.split('.')
            if (parts.size != 2) return null
            val major = parts[0].toIntOrNull()?.takeIf { it in 0..255 && parts[0].all(Char::isDigit) } ?: return null
            val minor = parts[1].toIntOrNull()?.takeIf { it in 0..255 && parts[1].all(Char::isDigit) } ?: return null
            return ProtocolVersion(major, minor)
        }
    }
}

/** Bitmask khả năng (u32); hai bên dùng giao của hai tập: `a and b`. */
object Capabilities {
    const val H264 = 1L shl 0
    const val HEVC = 1L shl 1
    const val AUDIO_PCM = 1L shl 2
    const val AUDIO_AAC_ELD = 1L shl 3
    const val CLIPBOARD = 1L shl 4
    const val MEDIA_OVER_TCP = 1L shl 5
    const val TOUCH_INPUT = 1L shl 6
    const val HOT_RECONFIGURE = 1L shl 7
    const val VIDEO_PAUSE = 1L shl 8
    const val FILE_TRANSFER = 1L shl 9
    const val REMOTE_UNLOCK = 1L shl 10
    const val MEDIA_KEYS = 1L shl 11
    const val MULTI_DISPLAY = 1L shl 12
}
