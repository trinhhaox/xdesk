package vn.xox.xdesk.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import vn.xox.xdesk.app.input.PointerMode
import vn.xox.xdesk.app.input.PointerSettings

/** Cài đặt con trỏ lưu trong SharedPreferences; đổi là lưu ngay và là state Compose để UI/router cập nhật. */
class PointerSettingsStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    var settings by mutableStateOf(load())
        private set

    fun update(change: (PointerSettings) -> PointerSettings) {
        val next = change(settings).let { it.copy(speed = it.safeSpeed) }
        settings = next
        prefs.edit()
            .putString(MODE, next.mode.name)
            .putFloat(SPEED, next.speed)
            .putBoolean(NATURAL, next.naturalScroll)
            .putBoolean(LONG_PRESS, next.longPressRightClick)
            .putBoolean(DOUBLE_TAP_KEYBOARD, next.doubleTapOpensKeyboard)
            .apply()
    }

    fun toggleMode() = update { it.copy(mode = if (it.mode == PointerMode.DIRECT) PointerMode.TRACKPAD else PointerMode.DIRECT) }

    private fun load(): PointerSettings {
        val fallback = PointerSettings()
        return PointerSettings(
            mode = prefs.getString(MODE, null)?.let { name -> PointerMode.entries.firstOrNull { it.name == name } } ?: fallback.mode,
            speed = PointerSettings.clampSpeed(prefs.getFloat(SPEED, fallback.speed)),
            naturalScroll = prefs.getBoolean(NATURAL, fallback.naturalScroll),
            longPressRightClick = prefs.getBoolean(LONG_PRESS, fallback.longPressRightClick),
            doubleTapOpensKeyboard = prefs.getBoolean(DOUBLE_TAP_KEYBOARD, fallback.doubleTapOpensKeyboard),
        )
    }

    private companion object {
        const val FILE = "xdesk_pointer"
        const val MODE = "mode"
        const val SPEED = "speed"
        const val NATURAL = "natural_scroll"
        const val LONG_PRESS = "long_press_right_click"
        const val DOUBLE_TAP_KEYBOARD = "double_tap_opens_keyboard"
    }
}
