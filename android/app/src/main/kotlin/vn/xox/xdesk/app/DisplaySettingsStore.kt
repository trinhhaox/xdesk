package vn.xox.xdesk.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import vn.xox.xdesk.media.AndroidCodecList
import vn.xox.xdesk.wire.MirrorFit
import vn.xox.xdesk.wire.ScreenMode
import vn.xox.xdesk.wire.VideoCodec

/** Chế độ làm việc mặc định, hiển thị, kiểu chiếu, tốc độ khung hình và bộ mã hoá video; lưu trong SharedPreferences. */
class DisplaySettingsStore(
    context: Context,
    val supportsHevc: Boolean = detectHardwareHevc(),
) {
    private val prefs = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    var mode by mutableStateOf(ScreenMode.entries.firstOrNull { it.name == prefs.getString(MODE, null) } ?: ScreenMode.MIRROR)
        private set

    var defaultWorkMode by mutableStateOf(WorkMode.fromStorage(prefs.getString(WORK_MODE, null), mode))
        private set

    var fit by mutableStateOf(MirrorFit.entries.firstOrNull { it.name == prefs.getString(FIT, null) && it in SUPPORTED_FITS } ?: MirrorFit.FIT_DEVICE)
        private set

    var qualityPreset by mutableStateOf(
        StreamQualityPreset.entries.firstOrNull { it.name == prefs.getString(QUALITY_PRESET, null) } ?: StreamQualityPreset.STANDARD_60,
    )
        private set

    var videoCodec by mutableStateOf(loadCodec(prefs.getString(VIDEO_CODEC, null), supportsHevc))
        private set

    fun selectMode(next: ScreenMode) { mode = next; prefs.edit().putString(MODE, next.name).apply() }

    fun selectDefaultWorkMode(next: WorkMode) {
        defaultWorkMode = next
        prefs.edit().putString(WORK_MODE, next.name).apply()
        next.screenMode?.let(::selectMode)
    }

    fun selectFit(next: MirrorFit) {
        if (next !in SUPPORTED_FITS) return
        fit = next
        prefs.edit().putString(FIT, next.name).apply()
    }

    fun selectQualityPreset(next: StreamQualityPreset) {
        qualityPreset = next
        prefs.edit().putString(QUALITY_PRESET, next.name).apply()
    }

    fun selectVideoCodec(next: VideoCodec) {
        val resolved = if (next == VideoCodec.HEVC && !supportsHevc) VideoCodec.H264 else next
        videoCodec = resolved
        prefs.edit().putString(VIDEO_CODEC, resolved.name).apply()
    }

    companion object {
        val SUPPORTED_FITS = listOf(MirrorFit.NATIVE, MirrorFit.FIT_DEVICE, MirrorFit.TOUCH)
        private const val FILE = "xdesk_display"
        private const val MODE = "mode"
        private const val WORK_MODE = "work_mode"
        private const val FIT = "mirror_fit"
        private const val QUALITY_PRESET = "quality_preset"
        private const val VIDEO_CODEC = "video_codec"

        private fun detectHardwareHevc(): Boolean = try {
            AndroidCodecList.hasHardwareHevc()
        } catch (_: Throwable) {
            false
        }

        private fun loadCodec(saved: String?, supportsHevc: Boolean): VideoCodec {
            val parsed = VideoCodec.entries.firstOrNull { it.name == saved }
            if (parsed == VideoCodec.H264) return VideoCodec.H264
            if (parsed == VideoCodec.HEVC) return if (supportsHevc) VideoCodec.HEVC else VideoCodec.H264
            return if (supportsHevc) VideoCodec.HEVC else VideoCodec.H264
        }
    }
}
