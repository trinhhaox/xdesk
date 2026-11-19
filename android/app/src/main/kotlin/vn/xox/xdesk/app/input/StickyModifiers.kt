package vn.xox.xdesk.app.input

/**
 * Phím bổ trợ dính của thanh phím phụ: chạm một lần = áp cho phím kế tiếp rồi tự nhả,
 * chạm hai lần liên tiếp (trong [DOUBLE_TAP_MS]) = khoá cho tới khi chạm lần nữa. Bất biến: mỗi thao tác trả bản mới (dùng làm state Compose).
 */
class StickyModifiers private constructor(private val states: Map<Int, State>, private val lastBit: Int, private val lastMs: Long) {
    enum class State { OFF, ARMED, LOCKED }

    constructor() : this(emptyMap(), 0, 0L)

    fun state(bit: Int): State = states[bit] ?: State.OFF

    /** Các bổ trợ đang có hiệu lực (armed hoặc locked). */
    val active: Int get() = states.filterValues { it != State.OFF }.keys.fold(0) { acc, bit -> acc or bit }

    fun tap(bit: Int, nowMs: Long): StickyModifiers {
        val next = when (state(bit)) {
            State.OFF -> State.ARMED
            State.ARMED -> if (lastBit == bit && nowMs - lastMs <= DOUBLE_TAP_MS) State.LOCKED else State.OFF
            State.LOCKED -> State.OFF
        }
        return StickyModifiers(states + (bit to next), bit, nowMs)
    }

    /** Lấy bổ trợ cho một phím rồi nhả loại armed (loại locked giữ nguyên). */
    fun consume(): Pair<Int, StickyModifiers> =
        active to StickyModifiers(states.mapValues { if (it.value == State.ARMED) State.OFF else it.value }, lastBit, lastMs)

    companion object { const val DOUBLE_TAP_MS = 400L }
}

/** Dịch lên bao nhiêu để vùng vừa chạm nằm trên bàn phím. Chọn dịch thay vì thu nhỏ để giữ tỉ lệ 1:1 (chữ vẫn đọc được khi nằm ngang). */
object VideoPan {
    const val DEFAULT_MARGIN = 28f

    /**
     * Độ dịch lên (≥ 0, px). `focusY`: y của vùng cần thấy (chưa dịch); `obscuredHeight`: bàn phím + thanh phím phụ che đáy;
     * `videoBottom`: đáy video (không dịch quá mức cần để thấy đáy).
     */
    fun offset(focusY: Float, viewHeight: Float, obscuredHeight: Float, videoBottom: Float, margin: Float = DEFAULT_MARGIN): Float {
        if (!(focusY.isFinite() && viewHeight.isFinite() && obscuredHeight.isFinite() && videoBottom.isFinite()) || obscuredHeight <= 0f) return 0f
        val visibleBottom = viewHeight - obscuredHeight
        val needed = focusY + margin - visibleBottom
        val useful = videoBottom - visibleBottom
        return maxOf(0f, minOf(needed, obscuredHeight, useful))
    }
}
