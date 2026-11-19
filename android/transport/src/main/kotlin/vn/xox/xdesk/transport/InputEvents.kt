package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.InputEvent
import vn.xox.xdesk.wire.InputKind

/** Bit `mods` của [InputEvent] (spec media-packets.md). */
object InputModifiers {
    const val SHIFT = 1
    const val CONTROL = 2
    const val OPTION = 4
    const val COMMAND = 8
    const val CAPS_LOCK = 16
    const val FUNCTION = 32
}

/** Giá trị `button` của down/up. */
object InputButton {
    const val LEFT = 0
    const val RIGHT = 1
    const val OTHER = 2
}

/** Dựng sự kiện đúng ngữ nghĩa trên dây; `seq` = 0 (do [InputSequencer] cấp cho sự kiện cần tin cậy). */
object InputEvents {
    fun move(x: Float, y: Float, mods: Int = 0) = InputEvent(InputKind.MOVE, mods = mods, seq = 0, x = x, y = y)

    /** `clickCount` (1, 2, 3…) đi trong `dx`. */
    fun button(down: Boolean, x: Float, y: Float, button: Int = InputButton.LEFT, clickCount: Int = 1, mods: Int = 0) =
        InputEvent(if (down) InputKind.DOWN else InputKind.UP, button, mods, 0, x, y, dx = clickCount.toFloat())

    /** Cuộn theo pixel điểm của host; `dy` > 0 = nội dung đi xuống (ngón kéo xuống). */
    fun scroll(dx: Float, dy: Float, mods: Int = 0) = InputEvent(InputKind.SCROLL, mods = mods, seq = 0, dx = dx, dy = dy)

    /** Phím theo HID usage; `button` = 1 nhấn, 0 nhả. */
    fun key(usage: Int, down: Boolean, mods: Int = 0) =
        InputEvent(InputKind.KEY, if (down) 1 else 0, mods, 0, keyUsage = usage)

    /** Cuộn (0, 0): host coi là còn sống, tránh watchdog nhả nút đang giữ. */
    val heartbeat: InputEvent = scroll(0f, 0f)

    /** Ép toạ độ vào 0…1 cho sự kiện con trỏ; `null` nếu có số không hữu hạn (bộ mã hoá từ chối cả lô nếu có một sự kiện sai). */
    fun sanitized(event: InputEvent): InputEvent? {
        if (!(event.x.isFinite() && event.y.isFinite() && event.dx.isFinite() && event.dy.isFinite())) return null
        val pointer = event.kind == InputKind.MOVE || event.kind == InputKind.DOWN || event.kind == InputKind.UP || event.kind == InputKind.TOUCH
        return if (pointer) event.copy(x = event.x.coerceIn(0f, 1f), y = event.y.coerceIn(0f, 1f)) else event
    }
}

/** Down/up/key cần giao chắc chắn (seq + input-ack); move/scroll bỏ mất cũng được. */
val InputEvent.isReliable: Boolean get() = kind == InputKind.DOWN || kind == InputKind.UP || kind == InputKind.KEY
