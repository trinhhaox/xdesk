package vn.xox.xdesk.media

/**
 * Đo độ trễ "khung vào → khung ra" của decoder: mỗi frame đưa vào được ghi giờ theo `pts`; khi decoder xuất frame đó
 * thì lag = giờ ra − giờ vào, và `framesHeld` = số frame đã vào nhưng chưa ra tại thời điểm đó (≈ độ sâu bộ đệm của codec).
 * Decoder không giữ frame cho `framesHeld` ≈ 0 hoặc 1. Không thread-safe: gọi từ một thread (callback decoder).
 */
class FrameLagMeter(private val windowSize: Int = 120) {
    class Report(val samples: Int, val p50Ms: Double, val p95Ms: Double, val maxMs: Double, val avgFramesHeld: Double, val maxFramesHeld: Int)

    private val enteredAtNs = HashMap<Long, Long>()
    private val lagsMs = ArrayList<Double>()
    private val heldSamples = ArrayList<Int>()
    private var inCount = 0L
    private var outCount = 0L

    fun onInput(ptsUs: Long, nowNs: Long) {
        enteredAtNs[ptsUs] = nowNs
        inCount++
    }

    /** Trả báo cáo khi đủ `windowSize` mẫu (rồi bắt đầu cửa sổ mới), ngược lại `null`. */
    fun onOutput(ptsUs: Long, nowNs: Long): Report? {
        val entered = enteredAtNs.remove(ptsUs) ?: return null
        outCount++
        lagsMs += (nowNs - entered) / 1_000_000.0
        heldSamples += (inCount - outCount).toInt()
        if (lagsMs.size < windowSize) return null
        return report().also { lagsMs.clear(); heldSamples.clear() }
    }

    /** Frame bị bỏ/hết hiệu lực: không bao giờ ra nên không tính vào lag, nhưng phải thôi tính là "đang giữ". */
    fun onDropped(ptsUs: Long) {
        if (enteredAtNs.remove(ptsUs) != null) inCount--
    }

    fun reset() {
        enteredAtNs.clear(); lagsMs.clear(); heldSamples.clear()
        inCount = 0; outCount = 0
    }

    private fun report(): Report {
        val sorted = lagsMs.sorted()
        fun pct(p: Double) = sorted[((sorted.size - 1) * p).toInt()]
        return Report(sorted.size, pct(0.5), pct(0.95), sorted.last(), heldSamples.average(), heldSamples.max())
    }
}
