package vn.xox.xdesk.media

/**
 * Đo độ trễ "khung vào → khung ra" của decoder, tách hai hiện tượng mà số "frame đang bay" đơn thuần không phân biệt được:
 *  - **inFlight** = frame đã vào chưa ra lúc một frame ra. Qua mạng giật, nhiều frame tới cùng lúc nên số này phình ra dù
 *    decoder không giữ gì (chỉ là hàng đợi đầu vào đang chờ giải mã).
 *  - **stuck** = frame còn kẹt khi decoder đã im lặng ≥ [quietNs] (không vào, không ra). Chỉ decoder giữ khung mới tạo được
 *    tình trạng này, nên đó là độ sâu bộ đệm thật. Lag của frame kẹt được tách khỏi p50/p95/max (nó là thời gian chờ khung
 *    kế, không phải độ trễ giải mã).
 *  - **skipped** = frame vào nhưng decoder xuất một frame mới hơn mà không bao giờ xuất nó (decoder bỏ khung). Không có reorder
 *    (host tắt B-frame) nên output theo đúng thứ tự vào; frame cũ hơn frame vừa ra mà chưa ra thì đã mất, không phải đang giữ.
 *    Nếu không loại chúng khỏi "đang giữ" thì mỗi frame bị bỏ làm số này tăng mãi, giống hệt decoder giữ khung.
 * Không thread-safe: gọi từ một thread (callback decoder), trừ [held] đọc được từ thread khác.
 */
class FrameLagMeter(private val windowSize: Int = 120, private val quietNs: Long = DEFAULT_QUIET_NS) {
    class Report(
        val samples: Int, val p50Ms: Double, val p95Ms: Double, val maxMs: Double,
        val avgInFlight: Double, val maxInFlight: Int,
        val stuckEvents: Int, val avgStuckFrames: Double, val maxStuckFrames: Int, val maxStuckLagMs: Double,
        val skipped: Int, val skippedWhileStuck: Int, val unknownOutputs: Int,
    )

    private val enteredAtNs = LinkedHashMap<Long, Long>()
    private val stuckPts = HashSet<Long>()
    private val lagsMs = ArrayList<Double>()
    private val inFlightSamples = ArrayList<Int>()
    private val stuckDepths = ArrayList<Int>()
    private var maxStuckLagMs = 0.0
    private var skipped = 0
    private var skippedWhileStuck = 0
    private var unknownOutputs = 0
    private var lastEventNs = 0L
    @Volatile private var inCount = 0L
    @Volatile private var outCount = 0L

    /** Số frame đã vào decoder nhưng chưa ra (đọc được từ thread khác); lúc decoder im lặng chính là độ sâu bộ đệm. */
    val held: Int get() = (inCount - outCount).toInt()

    fun onInput(ptsUs: Long, nowNs: Long) {
        val inFlight = enteredAtNs.size
        if (outCount > 0 && inFlight > 0 && nowNs - lastEventNs >= quietNs) { // chưa có output nào = decoder đang khởi động, không phải giữ khung
            stuckDepths += inFlight
            stuckPts += enteredAtNs.keys
        }
        lastEventNs = nowNs
        enteredAtNs[ptsUs] = nowNs
        inCount++
    }

    /** Trả báo cáo khi đủ `windowSize` mẫu (rồi bắt đầu cửa sổ mới), ngược lại `null`. */
    fun onOutput(ptsUs: Long, nowNs: Long): Report? {
        val entered = enteredAtNs[ptsUs]
        if (entered == null) { unknownOutputs++; return null }
        lastEventNs = nowNs
        retireUpTo(ptsUs)
        outCount++
        val lagMs = (nowNs - entered) / 1_000_000.0
        if (stuckPts.remove(ptsUs)) {
            maxStuckLagMs = maxOf(maxStuckLagMs, lagMs)
            return null
        }
        lagsMs += lagMs
        inFlightSamples += (inCount - outCount).toInt()
        if (lagsMs.size < windowSize) return null
        return report().also { clearWindow() }
    }

    /** Xoá `ptsUs` và mọi frame vào trước nó (decoder đã bỏ qua); các frame bỏ qua được tính là đã ra để không phình "đang giữ". */
    private fun retireUpTo(ptsUs: Long) {
        val it = enteredAtNs.entries.iterator()
        while (it.hasNext()) {
            val e = it.next()
            it.remove()
            if (e.key == ptsUs) return
            if (stuckPts.remove(e.key)) skippedWhileStuck++
            skipped++
            outCount++
        }
    }

    /** Frame bị bỏ/hết hiệu lực: không bao giờ ra nên không tính vào lag, nhưng phải thôi tính là "đang giữ". */
    fun onDropped(ptsUs: Long) {
        stuckPts.remove(ptsUs)
        if (enteredAtNs.remove(ptsUs) != null) inCount--
    }

    fun reset() {
        enteredAtNs.clear(); stuckPts.clear(); clearWindow()
        inCount = 0; outCount = 0; lastEventNs = 0
    }

    private fun clearWindow() {
        lagsMs.clear(); inFlightSamples.clear(); stuckDepths.clear(); maxStuckLagMs = 0.0; skipped = 0; skippedWhileStuck = 0; unknownOutputs = 0
    }

    private fun report(): Report {
        val sorted = lagsMs.sorted()
        fun pct(p: Double) = sorted[((sorted.size - 1) * p).toInt()]
        return Report(
            sorted.size, pct(0.5), pct(0.95), sorted.last(), inFlightSamples.average(), inFlightSamples.max(),
            stuckDepths.size, stuckDepths.averageOrZero(), stuckDepths.maxOrNull() ?: 0, maxStuckLagMs,
            skipped, skippedWhileStuck, unknownOutputs,
        )
    }

    private fun List<Int>.averageOrZero() = if (isEmpty()) 0.0 else average()

    companion object {
        /** Decoder bình thường xuất frame trong vài chục ms; im lặng 100 ms mà còn frame tức là decoder đang giữ nó. */
        const val DEFAULT_QUIET_NS = 100_000_000L
    }
}
