package vn.xox.xdesk.app.input

import android.view.KeyEvent
import vn.xox.xdesk.transport.InputModifiers

/** HID usage (USB HID Usage Tables, trang Keyboard) cho phím đặc biệt và ánh xạ từ `KeyEvent.KEYCODE_*` của Android. */
object HidKeys {
    const val ENTER = 0x28
    const val ESCAPE = 0x29
    const val BACKSPACE = 0x2A
    const val TAB = 0x2B
    const val SPACE = 0x2C
    const val RIGHT = 0x4F
    const val LEFT = 0x50
    const val DOWN = 0x51
    const val UP = 0x52
    const val DELETE_FORWARD = 0x4C
    const val HOME = 0x4A
    const val END = 0x4D
    const val PAGE_UP = 0x4B
    const val PAGE_DOWN = 0x4E

    /** `null` nếu phím không có ánh xạ (bỏ qua, không gửi). */
    fun fromAndroid(keyCode: Int): Int? = when (keyCode) {
        in KeyEvent.KEYCODE_A..KeyEvent.KEYCODE_Z -> 0x04 + (keyCode - KeyEvent.KEYCODE_A)
        in KeyEvent.KEYCODE_1..KeyEvent.KEYCODE_9 -> 0x1E + (keyCode - KeyEvent.KEYCODE_1)
        KeyEvent.KEYCODE_0 -> 0x27
        in KeyEvent.KEYCODE_F1..KeyEvent.KEYCODE_F12 -> 0x3A + (keyCode - KeyEvent.KEYCODE_F1)
        KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> ENTER
        KeyEvent.KEYCODE_ESCAPE -> ESCAPE
        KeyEvent.KEYCODE_DEL -> BACKSPACE
        KeyEvent.KEYCODE_FORWARD_DEL -> DELETE_FORWARD
        KeyEvent.KEYCODE_TAB -> TAB
        KeyEvent.KEYCODE_SPACE -> SPACE
        KeyEvent.KEYCODE_DPAD_RIGHT -> RIGHT
        KeyEvent.KEYCODE_DPAD_LEFT -> LEFT
        KeyEvent.KEYCODE_DPAD_DOWN -> DOWN
        KeyEvent.KEYCODE_DPAD_UP -> UP
        KeyEvent.KEYCODE_MOVE_HOME -> HOME
        KeyEvent.KEYCODE_MOVE_END -> END
        KeyEvent.KEYCODE_PAGE_UP -> PAGE_UP
        KeyEvent.KEYCODE_PAGE_DOWN -> PAGE_DOWN
        else -> null
    }

    /** HID usage của ký tự gõ được bằng một phím không cần Shift (a–z, 0–9, dấu cách); dùng khi có bổ trợ dính (⌘ + "c" → ⌘C). */
    fun fromChar(c: Char): Int? = when (c) {
        in 'a'..'z' -> 0x04 + (c - 'a')
        in '1'..'9' -> 0x1E + (c - '1')
        '0' -> 0x27
        ' ' -> SPACE
        else -> null
    }

    /** Bit `mods` của host từ trạng thái meta của Android (Alt → Option, Meta → Command). */
    fun modifiers(metaState: Int): Int {
        var mods = 0
        if (metaState and KeyEvent.META_SHIFT_ON != 0) mods = mods or InputModifiers.SHIFT
        if (metaState and KeyEvent.META_CTRL_ON != 0) mods = mods or InputModifiers.CONTROL
        if (metaState and KeyEvent.META_ALT_ON != 0) mods = mods or InputModifiers.OPTION
        if (metaState and KeyEvent.META_META_ON != 0) mods = mods or InputModifiers.COMMAND
        return mods
    }
}
