package vn.xox.xdesk.transport

import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import vn.xox.xdesk.wire.MediaPacket

/**
 * Tách giải mã/phát audio khỏi luồng nhận UDP: [onPacket] chỉ xếp gói vào hàng đợi có giới hạn rồi trả về ngay.
 * Nếu decoder (MediaCodec AAC-ELD trên một số chip) chậm hay treo, luồng UDP vẫn gửi keepalive nên phiên không bị
 * host cắt vì "mất liên lạc"; hàng đầy thì bỏ gói cũ nhất (audio trễ còn tệ hơn mất vài ms).
 */
class AsyncAudioSink(
    private val delegate: AudioSink,
    capacity: Int = DEFAULT_CAPACITY,
    private val threadName: String = "xdesk-audio-decode",
) : AudioSink {
    private val queue = ArrayBlockingQueue<MediaPacket>(capacity)
    @Volatile private var running = false
    private var worker: Thread? = null

    @Volatile var droppedPackets = 0L
        private set

    @Synchronized
    override fun start() {
        if (running) return
        running = true
        delegate.start()
        worker = Thread({ drainLoop() }, threadName).apply {
            isDaemon = true
            start()
        }
    }

    override fun onPacket(packet: MediaPacket) {
        if (!running) return
        while (!queue.offer(packet)) {
            if (queue.poll() != null) droppedPackets++
        }
    }

    @Synchronized
    override fun stop() {
        if (!running) return
        running = false
        worker?.interrupt()
        worker?.join(STOP_JOIN_MS)
        worker = null
        queue.clear()
        delegate.stop()
    }

    private fun drainLoop() {
        while (running) {
            val packet = try {
                queue.poll(POLL_MS, TimeUnit.MILLISECONDS)
            } catch (e: InterruptedException) {
                return
            } ?: continue
            delegate.onPacket(packet)
        }
    }

    companion object {
        /** ~0,3 s audio ở 5 ms/gói. */
        const val DEFAULT_CAPACITY = 64
        private const val POLL_MS = 100L
        private const val STOP_JOIN_MS = 500L
    }
}
