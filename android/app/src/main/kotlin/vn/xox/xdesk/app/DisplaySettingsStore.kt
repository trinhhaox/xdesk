package vn.xox.xdesk.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import vn.xox.xdesk.wire.MirrorFit
import vn.xox.xdesk.wire.ScreenMode

/** Chế độ hiển thị (mặc định Bản sao) và kiểu vừa khung của Bản sao; lưu trong SharedPreferences, là state Compose. */
class DisplaySettingsStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    var mode by mutableStateOf(ScreenMode.entries.firstOrNull { it.name == prefs.getString(MODE, null) } ?: ScreenMode.MIRROR)
        private set

    /** Android chưa có letterbox + zoom nên chỉ cung cấp [SUPPORTED_FITS]; giá trị lưu khác (vd. NATIVE) về mặc định. */
    var fit by mutableStateOf(MirrorFit.entries.firstOrNull { it.name == prefs.getString(FIT, null) && it in SUPPORTED_FITS } ?: MirrorFit.FIT_DEVICE)
        private set

    fun selectMode(next: ScreenMode) { mode = next; prefs.edit().putString(MODE, next.name).apply() }

    fun selectFit(next: MirrorFit) {
        if (next !in SUPPORTED_FITS) return
        fit = next
        prefs.edit().putString(FIT, next.name).apply()
    }

    companion object {
        val SUPPORTED_FITS = listOf(MirrorFit.FIT_DEVICE, MirrorFit.TOUCH)
        private const val FILE = "xdesk_display"
        private const val MODE = "mode"
        private const val FIT = "mirror_fit"
    }
}
