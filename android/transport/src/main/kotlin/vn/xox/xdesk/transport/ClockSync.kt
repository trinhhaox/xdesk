package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.ControlMessage

/** Một mẫu ping/pong 4 mốc (ms): `t0` viewer gửi, `t1` host nhận, `t2` host gửi, `t3` viewer nhận. */
data class ClockSample(val t0: Long, val t1: Long, val t2: Long, val t3: Long) {
    constructor(pong: ControlMessage.Pong, receivedAtMs: Long) : this(pong.t0, pong.t1, pong.t2, receivedAtMs)

    /** Độ lệch đồng hồ host − viewer. */
    val offsetMs: Double get() = ((t1 - t0) + (t2 - t3)) / 2.0

    /** RTT mạng đã trừ thời gian xử lý ở host. */
    val rttMs: Long get() = (t3 - t0) - (t2 - t1)

    val isValid: Boolean get() = rttMs >= 0 && t2 >= t1 && t3 >= t0
}

/** Giữ [windowSize] mẫu gần nhất, dùng mẫu có RTT nhỏ nhất (đường đi đối xứng nhất, sai số ≤ rtt/2). Không đọc đồng hồ. */
class ClockSync(windowSize: Int = 8) {
    private val windowSize = maxOf(1, windowSize)
    private val samples = ArrayDeque<ClockSample>()

    /** Mẫu không hợp lệ bị từ chối (`false`). */
    fun add(sample: ClockSample): Boolean {
        if (!sample.isValid) return false
        samples.addLast(sample)
        while (samples.size > windowSize) samples.removeFirst()
        return true
    }

    val sampleCount: Int get() = samples.size
    private val best: ClockSample? get() = samples.minByOrNull { it.rttMs }

    /** host − viewer (ms); `null` khi chưa có mẫu. */
    val offsetMs: Double? get() = best?.offsetMs
    val rttMs: Long? get() = best?.rttMs

    fun viewerToHostMs(viewerMs: Long): Long? = offsetMs?.let { viewerMs + Math.round(it) }
    fun hostToViewerMs(hostMs: Long): Long? = offsetMs?.let { hostMs - Math.round(it) }

    companion object {
        fun wallClockMs(): Long = System.currentTimeMillis()
    }
}
