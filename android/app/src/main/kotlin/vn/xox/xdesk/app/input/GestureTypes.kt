package vn.xox.xdesk.app.input

enum class TouchPhase { BEGAN, MOVED, ENDED, CANCELLED }

/** Một mẫu chạm: toạ độ chuẩn hoá 0…1 trên khung video, thời gian đơn điệu (ms). */
data class TouchSample(val id: Int, val x: Float, val y: Float, val phase: TouchPhase, val timeMs: Long)

/** `surfaceWidth/Height`: kích thước màn hình host theo điểm; đổi delta chuẩn hoá → pixel và đo ngưỡng di chuyển. */
data class GestureConfig(
    val surfaceWidth: Float,
    val surfaceHeight: Float,
    val longPressMs: Long = 500,
    val doubleTapMs: Long = 300,
    val twoFingerTapMs: Long = 300,
    /** Di chuyển dưới ngưỡng này (điểm host) vẫn tính là chạm. */
    val slop: Float = 8f,
    /** Ngưỡng chạm theo dp trên màn hình điện thoại: ngón tay rung ~10 dp là bình thường. */
    val viewSlop: Float = 10f,
    /**
     * Số điểm host ứng với một dp màn hình (theo cỡ video đang hiện, kể cả zoom); 0 = chưa biết. Màn Mac lớn hiện trên
     * điện thoại nhỏ thì 8 điểm host chỉ còn ~3 dp dưới ngón: chạm dễ bị hiểu thành vuốt.
     */
    val hostPointsPerViewPoint: Float = 0f,
    /** Giữ một ngón đủ [longPressMs] rồi nhả (không kéo) = click phải; tắt thì nhả ra là click trái. */
    val longPressRightClick: Boolean = true,
    /** Cuộn tự nhiên: nội dung đi theo ngón tay; tắt thì đảo chiều. */
    val naturalScroll: Boolean = true,
)

/** Ngưỡng thực dùng (điểm host): lớn hơn trong hai ngưỡng. */
internal val GestureConfig.effectiveSlop: Float get() = maxOf(slop, viewSlop * hostPointsPerViewPoint)
