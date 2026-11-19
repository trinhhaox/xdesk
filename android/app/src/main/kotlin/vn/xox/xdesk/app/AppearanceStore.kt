package vn.xox.xdesk.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Giao diện app: mặc định Tối; `SYSTEM` theo cài đặt Sáng/Tối của điện thoại. */
enum class AppearanceSetting { DARK, LIGHT, SYSTEM }

/** Lưu lựa chọn giao diện trong SharedPreferences; là state Compose nên đổi là áp dụng ngay. */
class AppearanceStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    var setting by mutableStateOf(AppearanceSetting.entries.firstOrNull { it.name == prefs.getString(KEY, null) } ?: AppearanceSetting.DARK)
        private set

    fun select(next: AppearanceSetting) {
        setting = next
        prefs.edit().putString(KEY, next.name).apply()
    }

    private companion object {
        const val FILE = "xdesk_appearance"
        const val KEY = "appearance"
    }
}
