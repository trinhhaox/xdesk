package vn.xox.xdesk.media

import vn.xox.xdesk.wire.AudioCodec
import vn.xox.xdesk.wire.AudioPayload
import vn.xox.xdesk.wire.MediaPacket
import vn.xox.xdesk.wire.MediaPacketType
import vn.xox.xdesk.wire.WireException

/** Nhận s16 xen kẽ 48 kHz stereo và đưa ra loa; `write` được phép chặn (nhịp phát do thiết bị quyết định). */
interface PcmOutput {
    val outputLatencyMs: Int
    fun start()
    fun write(samples: ShortArray)
    fun stop()
}

/** Giải một access unit AAC-ELD thô → s16 xen kẽ. */
interface AacEldUnitDecoder {
    fun decode(unit: ByteArray): ShortArray
    fun release()
}

/** Số liệu phát audio (đọc từ luồng bất kỳ). */
data class AudioPlayerStats(
    val packets: Int = 0,
    val malformed: Int = 0,
    val codec: AudioCodec? = null,
    val jitterDepthMs: Int = 0,
    val underruns: Int = 0,
    val concealedFrames: Int = 0,
    val outputLatencyMs: Int = 0,
    /** Host giữ đoạn mới nhất bao lâu từ lúc ghi tới lúc gửi (ms). */
    val hostHoldMs: Int = 0,
) {
    /** Ước lượng trễ đầu-cuối: host giữ + mạng một chiều (rtt/2) + jitter buffer + thiết bị phát. */
    fun estimatedLatencyMs(rttMs: Long): Long = hostHoldMs + rttMs / 2 + jitterDepthMs + outputLatencyMs
}

/**
 * Phát audio nhận được: giải mã PCM / AAC-ELD → [AudioJitterBuffer] (40 ms) → [PcmOutput] (AudioTrack độ trễ thấp).
 * [ingest] gọi từ luồng nhận UDP và phải nhanh; một luồng riêng rút từ jitter buffer theo nhịp ghi của thiết bị.
 */
class AudioPlayer(
    private val output: PcmOutput,
    private val decoderFactory: () -> AacEldUnitDecoder,
) {
    private val lock = Any()
    private val jitter = AudioJitterBuffer()
    private var decoder: AacEldUnitDecoder? = null
    private var packets = 0
    private var malformed = 0
    private var codec: AudioCodec? = null
    private var hostHoldMs = 0
    private var thread: Thread? = null
    @Volatile private var running = false

    val stats: AudioPlayerStats
        get() = synchronized(lock) {
            AudioPlayerStats(
                packets, malformed, codec, jitter.depthMs, jitter.counters.underruns, jitter.counters.concealedFrames,
                output.outputLatencyMs, hostHoldMs,
            )
        }

    fun start() {
        if (running) return
        running = true
        output.start()
        thread = Thread({ while (running) pump(PUMP_FRAMES) }, "xdesk-audio").apply {
            priority = Thread.MAX_PRIORITY
            isDaemon = true
            start()
        }
    }

    fun stop() {
        if (running) {
            running = false
            thread?.join(500)
            thread = null
            output.stop()
        }
        synchronized(lock) {
            decoder?.release()
            decoder = null
            jitter.reset()
            packets = 0
            malformed = 0
            codec = null
            hostHoldMs = 0
        }
    }

    /** Nhận một gói media ptype 0x20. Gói sai chỉ bị đếm, không bao giờ ném lỗi ra ngoài. */
    fun ingest(packet: MediaPacket) {
        if (packet.header.type != MediaPacketType.AUDIO) return
        try {
            val payload = AudioPayload.decode(packet.payload)
            val pcm = samples(payload)
            synchronized(lock) {
                packets++
                codec = payload.codec
                hostHoldMs = payload.holdMs
                jitter.push(packet.header.frameNo, pcm)
            }
        } catch (e: WireException) {
            synchronized(lock) { malformed++ }
        } catch (e: RuntimeException) {
            // MediaCodec hỏng trên gói này: bỏ gói, đếm lỗi; tạo lại decoder ở gói kế.
            synchronized(lock) {
                malformed++
                decoder?.release()
                decoder = null
            }
        }
    }

    /** Rút [frames] mẫu/kênh từ jitter buffer và ghi ra thiết bị (luồng phát; test gọi trực tiếp). */
    internal fun pump(frames: Int) {
        val pcm = synchronized(lock) { jitter.pull(frames) }
        output.write(pcm)
    }

    private fun samples(payload: AudioPayload): ShortArray = when (payload.codec) {
        AudioCodec.PCM -> pcmFromLittleEndian(payload.data)
        AudioCodec.AAC_ELD -> synchronized(lock) { decoder ?: decoderFactory().also { decoder = it } }.decode(payload.data)
    }

    companion object {
        /** 5 ms mỗi lần ghi. */
        const val PUMP_FRAMES = 240

        internal fun pcmFromLittleEndian(data: ByteArray): ShortArray =
            ShortArray(data.size / 2) { i -> ((data[2 * i].toInt() and 0xFF) or (data[2 * i + 1].toInt() shl 8)).toShort() }
    }
}
