package vn.xox.xdesk.media

import vn.xox.xdesk.wire.AudioPayload

/**
 * Bộ đệm chống rung cho audio phía viewer (thuần logic, test được trên JVM; cùng hành vi bản Swift `AudioJitterBuffer`).
 * Mẫu s16 xen kẽ L,R. Bắt đầu phát khi đủ [TARGET_MS]; thiếu → phát im lặng và đệm lại; dư quá [OVERFLOW_MS] → bỏ phần cũ về
 * [TARGET_MS] (ưu tiên trễ thấp hơn lip-sync tuyệt đối). Khoảng trống số thứ tự được lấp bằng im lặng. Không thread-safe.
 */
class AudioJitterBuffer {
    class Counters {
        var packetsAccepted = 0
        var lateOrDuplicate = 0
        var concealedFrames = 0
        var underruns = 0
        var overflowTrims = 0
        var resets = 0
    }

    val counters = Counters()
    private var samples = ShortArray(INITIAL_CAPACITY)
    private var head = 0
    private var size = 0
    private var started = false
    private var lastSequence: Long? = null
    private var lastPacketFrames = AudioPayload.PCM_FRAMES_PER_PACKET

    /** Số mẫu/kênh đang chờ phát. */
    val bufferedFrames: Int get() = size / CHANNELS
    val depthMs: Int get() = bufferedFrames / FRAMES_PER_MS

    /** Nhận một gói đã giải mã (s16 xen kẽ). Gói cũ/trùng bị bỏ. */
    fun push(sequence: Long, pcm: ShortArray) {
        if (pcm.isEmpty() || pcm.size % CHANNELS != 0) return
        val last = lastSequence
        if (last != null) {
            val gap = (sequence - last).toInt() - 1
            if (gap < 0) { counters.lateOrDuplicate++; return }
            if (gap > MAX_CONCEALED_PACKETS) reset() else if (gap > 0) conceal(gap)
        }
        lastSequence = sequence
        lastPacketFrames = pcm.size / CHANNELS
        append(pcm, pcm.size)
        counters.packetsAccepted++
        trimIfOverflowing()
    }

    /** Lấy đúng [frames] mẫu/kênh cho thiết bị phát; thiếu thì bù im lặng. */
    fun pull(frames: Int): ShortArray {
        val want = frames * CHANNELS
        val out = ShortArray(want)
        if (!started) {
            if (bufferedFrames < TARGET_MS * FRAMES_PER_MS) return out
            started = true
        }
        val available = minOf(want, size)
        for (i in 0 until available) out[i] = samples[(head + i) % samples.size]
        head = (head + available) % samples.size
        size -= available
        if (available < want) {
            started = false
            counters.underruns++
        }
        return out
    }

    fun reset() {
        head = 0
        size = 0
        started = false
        lastSequence = null
        counters.resets++
    }

    private fun conceal(packets: Int) {
        val frames = packets * lastPacketFrames
        append(ShortArray(frames * CHANNELS), frames * CHANNELS)
        counters.concealedFrames += frames
    }

    private fun append(source: ShortArray, count: Int) {
        if (size + count > samples.size) grow(size + count)
        val tail = (head + size) % samples.size
        for (i in 0 until count) samples[(tail + i) % samples.size] = source[i]
        size += count
    }

    private fun grow(needed: Int) {
        val bigger = ShortArray(maxOf(needed, samples.size * 2))
        for (i in 0 until size) bigger[i] = samples[(head + i) % samples.size]
        samples = bigger
        head = 0
    }

    private fun trimIfOverflowing() {
        if (depthMs <= OVERFLOW_MS) return
        val keep = TARGET_MS * FRAMES_PER_MS * CHANNELS
        val drop = size - keep
        head = (head + drop) % samples.size
        size = keep
        counters.overflowTrims++
    }

    companion object {
        const val TARGET_MS = 40
        const val OVERFLOW_MS = 100
        const val MAX_CONCEALED_PACKETS = 50
        private const val CHANNELS = AudioPayload.CHANNELS
        private const val FRAMES_PER_MS = AudioPayload.SAMPLE_RATE / 1000
        private const val INITIAL_CAPACITY = AudioPayload.SAMPLE_RATE * CHANNELS / 4
    }
}
