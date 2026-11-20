package vn.xox.xdesk.app.input

import vn.xox.xdesk.wire.InputEvent

/** Cách chạm điều khiển con trỏ Mac. */
enum class PointerMode {
    /** Chạm đâu click đó (màn hình cảm ứng). */
    DIRECT,

    /** Một ngón trượt như trackpad, con trỏ di chuyển tương đối. */
    TRACKPAD,
}

/** Cài đặt con trỏ, lưu theo app; cùng giá trị mặc định với viewer iOS. */
data class PointerSettings(
    val mode: PointerMode = PointerMode.DIRECT,
    val speed: Float = 1f,
    /** Cuộn tự nhiên: nội dung đi theo ngón tay. */
    val naturalScroll: Boolean = true,
    /** Nhấn giữ một ngón = click phải. */
    val longPressRightClick: Boolean = true,
) {
    /** Tốc độ luôn nằm trong [SPEED_RANGE]; số không hữu hạn (file cài đặt hỏng) quay về 1. */
    val safeSpeed: Float get() = clampSpeed(speed)

    companion object {
        val SPEED_RANGE = 0.5f..2.5f
        fun clampSpeed(value: Float): Float = if (value.isFinite()) value.coerceIn(SPEED_RANGE) else 1f
    }
}

/** Đường cong gia tốc của trackpad: trượt chậm thì con trỏ đi chậm để canh chính xác, vuốt nhanh thì đi xa. */
object PointerAcceleration {
    const val BASE_GAIN = 0.5f
    const val SLOPE = 1.5f
    const val MAX_GAIN = 3f

    /** `velocity` tính bằng chiều rộng màn hình host mỗi giây (ngón vuốt hết khung trong 1 s = 1). */
    fun gain(velocity: Float, speed: Float): Float {
        val v = if (velocity.isFinite()) maxOf(0f, velocity) else 0f
        return minOf(MAX_GAIN, BASE_GAIN + SLOPE * v) * PointerSettings.clampSpeed(speed)
    }
}

/** Bộ diễn giải cảm ứng → input host; `cursor` chỉ có ở chế độ trackpad (vị trí 0…1 do viewer tự giữ). */
interface PointerGestures {
    val cursor: Pair<Float, Float>? get() = null
    fun handle(s: TouchSample): List<InputEvent>
    fun tick(nowMs: Long): List<InputEvent>
    /** Đang giữ một ngón đủ lâu (sẵn sàng kéo thả / click phải): UI rung nhẹ khi trạng thái này bật lên. */
    val isHolding: Boolean get() = false
    /** Số điểm host ứng với một dp màn hình (cỡ video đang hiện, kể cả zoom) để ngưỡng chạm tính theo ngón tay. */
    fun setHostPointsPerViewPoint(scale: Float) {}
}

/** Dựng bộ diễn giải theo cài đặt; giữ vị trí con trỏ cũ khi đổi cài đặt giữa chừng. */
fun createPointerGestures(settings: PointerSettings, surfaceWidth: Float, surfaceHeight: Float, cursor: Pair<Float, Float>? = null): PointerGestures =
    when (settings.mode) {
        PointerMode.DIRECT -> GestureInterpreter(
            GestureConfig(surfaceWidth, surfaceHeight, longPressRightClick = settings.longPressRightClick, naturalScroll = settings.naturalScroll),
        )
        PointerMode.TRACKPAD -> TrackpadInterpreter(
            TrackpadConfig(surfaceWidth, surfaceHeight, settings.safeSpeed, settings.naturalScroll, settings.longPressRightClick),
            cursor ?: (0.5f to 0.5f),
        )
    }
