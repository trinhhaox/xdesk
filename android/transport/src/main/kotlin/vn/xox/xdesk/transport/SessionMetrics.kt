package vn.xox.xdesk.transport

/** Số liệu sống của một phiên: đồng hồ host, RTT, fps, kbps. Ghi từ nhiều thread nên các trường công khai là volatile. */
internal class SessionMetrics {
    private var clock = ClockSync()
    private var stats = ViewerStats()
    @Volatile var fps = 0
        private set
    @Volatile var recvKbps = 0
        private set
    @Volatile var rttMs: Long? = null
        private set
    @Volatile var clockOffsetMs: Double? = null
        private set

    @Synchronized fun updateClock(sample: ClockSample) {
        clock.add(sample)
        rttMs = clock.rttMs
        clockOffsetMs = clock.offsetMs
    }

    @Synchronized fun hostNowMs(): Long? = clock.viewerToHostMs(ClockSync.wallClockMs())

    @Synchronized fun recordFrame(frameNo: Long, bytes: Int) = stats.record(frameNo, bytes)

    @Synchronized fun closeWindow(nowMs: Long): ViewerStats.Window? = stats.closeWindow(nowMs)?.also {
        fps = it.fps
        recvKbps = it.recvKbps
    }

    @Synchronized fun reset() {
        clock = ClockSync()
        stats = ViewerStats()
        fps = 0; recvKbps = 0; rttMs = null; clockOffsetMs = null
    }
}
