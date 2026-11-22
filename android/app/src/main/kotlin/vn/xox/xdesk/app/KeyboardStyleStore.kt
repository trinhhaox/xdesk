package vn.xox.xdesk.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Kiểu bàn phím trong chế độ "Bàn phím ảo": phím Mac đầy đủ hoặc ô gõ văn bản. */
enum class KeyboardStyle(val title: String) {
    MAC("Bàn phím Mac"),
    TEXT("Gõ văn bản"),
}

/** Nhớ lựa chọn gần nhất trong SharedPreferences; là state Compose. Mặc định [KeyboardStyle.MAC]. */
class KeyboardStyleStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("xdesk_keyboard", Context.MODE_PRIVATE)

    var style by mutableStateOf(KeyboardStyle.entries.firstOrNull { it.name == prefs.getString(STYLE, null) } ?: KeyboardStyle.MAC)
        private set

    fun select(next: KeyboardStyle) {
        style = next
        prefs.edit().putString(STYLE, next.name).apply()
    }

    private companion object { const val STYLE = "style" }
}
