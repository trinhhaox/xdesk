package vn.xox.xdesk.transport

import kotlin.math.max
import kotlin.math.min

/**
 * Kiểu "Tối ưu thao tác" của Bản sao: độ phân giải logic thấp để nút macOS đủ to cho ngón tay (công thức như bản Swift,
 * xem protocol/spec/control-messages.md). Đơn vị điểm = dp của viewer: điều khiển macOS 22 pt phải thành ≥ 44 pt
 * (phóng đại lý tưởng 2×), nhưng logic không có cạnh ngắn nhỏ hơn 540 pt (macOS từ chối mode HiDPI ≤ 520) và phóng đại không bao giờ < 1×.
 */
object TouchScale {
    const val MAC_CONTROL_POINTS = 22.0
    const val MIN_TOUCH_POINTS = 44.0
    const val MIN_LOGICAL_SHORT = 540.0
    const val MIN_LOGICAL_LONG = 640.0

    fun magnification(pointsWidth: Double, pointsHeight: Double): Double {
        val short = min(pointsWidth, pointsHeight)
        val long = max(pointsWidth, pointsHeight)
        return minOf(MIN_TOUCH_POINTS / MAC_CONTROL_POINTS, short / MIN_LOGICAL_SHORT, long / MIN_LOGICAL_LONG)
    }

    /** Kích thước logic (điểm macOS) của desktop Mac; giữ chiều xoay và tỉ lệ viewer, mỗi cạnh làm tròn. */
    fun logicalSize(pointsWidth: Double, pointsHeight: Double): Pair<Double, Double> {
        val m = magnification(pointsWidth, pointsHeight)
        return Math.round(pointsWidth / m).toDouble() to Math.round(pointsHeight / m).toDouble()
    }
}
