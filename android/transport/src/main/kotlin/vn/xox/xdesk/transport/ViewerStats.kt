package vn.xox.xdesk.transport

/** Thống kê cửa sổ ngắn cho `net.report`: fps, kbps nhận và tỉ lệ frame mất (theo khoảng hở `frameNo`). Không thread-safe. */
class ViewerStats {
    class Window(val fps: Int, val recvKbps: Int, val lossPermille: Int)

    private var windowStartMs: Long? = null
    private var frames = 0
    private var bytes = 0L
    private var highestFrameNo = -1L
    private var expected = 0L
    private var received = 0L

    fun record(frameNo: Long, byteCount: Int) {
        frames++
        bytes += byteCount
        received++
        expected += if (highestFrameNo < 0) 1 else maxOf(0L, frameNo - highestFrameNo)
        highestFrameNo = maxOf(highestFrameNo, frameNo)
    }

    /** Đóng cửa sổ hiện tại; `null` ở lần gọi đầu (chỉ mở cửa sổ) hoặc khi chưa đủ 100 ms. */
    fun closeWindow(nowMs: Long): Window? {
        val start = windowStartMs
        windowStartMs = nowMs
        if (start == null || nowMs - start < 100) return null
        val elapsed = nowMs - start
        val loss = if (expected > 0) ((expected - received) * 1000 / expected).toInt().coerceIn(0, 1000) else 0
        val window = Window((frames * 1000L / elapsed).toInt(), (bytes * 8 / elapsed).toInt(), loss)
        frames = 0; bytes = 0; expected = 0; received = 0
        return window
    }
}
