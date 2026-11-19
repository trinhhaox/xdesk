package vn.xox.xdesk.app

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Vị trí nút điều khiển nổi: dính mép trái/phải, `fraction` 0…1 dọc theo đoạn di chuyển được. Mặc định giữa mép phải. */
data class FloatingPlacement(val trailing: Boolean = true, val fraction: Float = 0.5f) {
    /** Thả tay tại tâm (cx, cy): dính mép gần nhất theo chiều ngang, ép độ cao vào container. */
    companion object {
        fun snapped(cx: Float, cy: Float, width: Float, height: Float, size: Float) =
            FloatingPlacement(cx > width / 2, ((cy - size / 2) / maxOf(1f, height - size)).coerceIn(0f, 1f))
    }

    /** Góc trên-trái của nút (px) cách mép `margin`. */
    fun origin(width: Float, height: Float, size: Float, margin: Float): Pair<Float, Float> =
        (if (trailing) width - size - margin else margin) to (fraction.coerceIn(0f, 1f) * maxOf(0f, height - size))
}

/** Lưu [FloatingPlacement] trong SharedPreferences; là state Compose. */
class FloatingControlStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("xdesk_floating", Context.MODE_PRIVATE)

    var placement by mutableStateOf(FloatingPlacement(prefs.getBoolean(TRAILING, true), prefs.getFloat(FRACTION, 0.5f).takeIf { it.isFinite() } ?: 0.5f))
        private set

    fun save(next: FloatingPlacement) {
        placement = next
        prefs.edit().putBoolean(TRAILING, next.trailing).putFloat(FRACTION, next.fraction).apply()
    }

    private companion object {
        const val TRAILING = "trailing"
        const val FRACTION = "fraction"
    }
}
