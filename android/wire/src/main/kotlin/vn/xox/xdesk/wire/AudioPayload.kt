package vn.xox.xdesk.wire

/** Codec của gói audio (byte đầu payload của ptype 0x20). */
enum class AudioCodec(val raw: Int, val capability: Long) {
    /** s16 little-endian xen kẽ L,R. */
    PCM(0, Capabilities.AUDIO_PCM),
    /** Một access unit AAC-ELD thô (512 mẫu/kênh). */
    AAC_ELD(1, Capabilities.AUDIO_AAC_ELD);

    companion object {
        fun of(raw: Int): AudioCodec? = entries.firstOrNull { it.raw == raw }
    }
}

/** Payload gói audio: `u8 codec | u16 holdMs (BE) | data` (xem `media-packets.md`, mục Âm thanh). */
class AudioPayload(val codec: AudioCodec, val holdMs: Int, val data: ByteArray) {
    /** Số mẫu/kênh của gói (PCM: theo độ dài; AAC-ELD: cố định 512). */
    val frameCount: Int get() = if (codec == AudioCodec.PCM) data.size / BYTES_PER_FRAME else AAC_FRAMES_PER_UNIT

    fun encode(): ByteArray {
        validate()
        val w = ByteWriter(HEADER_SIZE + data.size)
        w.u8(codec.raw)
        w.u16(holdMs.coerceIn(0, 0xFFFF))
        w.append(data)
        return w.toByteArray()
    }

    /** Gói media ptype 0x20 không phân mảnh. */
    fun mediaPacket(streamId: Int, sequence: Long, ptsMs: Long): MediaPacket =
        MediaPacket(MediaHeader(MediaPacketType.AUDIO, streamId, sequence, ptsMs = ptsMs), encode())

    private fun validate() {
        if (data.isEmpty()) wireError(WireErrorCode.emptyPayload)
        if (data.size > MAX_DATA_SIZE) wireError(WireErrorCode.payloadTooLarge, "${data.size}")
        if (codec == AudioCodec.PCM && data.size % BYTES_PER_FRAME != 0) wireError(WireErrorCode.invalidField, "audio.pcm.length")
    }

    override fun equals(other: Any?): Boolean =
        other is AudioPayload && codec == other.codec && holdMs == other.holdMs && data.contentEquals(other.data)

    override fun hashCode(): Int = 31 * (31 * codec.hashCode() + holdMs) + data.contentHashCode()

    companion object {
        const val SAMPLE_RATE = 48_000
        const val CHANNELS = 2
        const val BYTES_PER_FRAME = 4
        /** Mẫu/kênh trong một gói PCM do host gửi (5 ms). */
        const val PCM_FRAMES_PER_PACKET = 240
        /** Mẫu/kênh trong một access unit AAC-ELD. */
        const val AAC_FRAMES_PER_UNIT = 512
        const val HEADER_SIZE = 3
        const val MAX_DATA_SIZE = MediaPacket.MAX_PAYLOAD - HEADER_SIZE

        /** AudioSpecificConfig của AAC-ELD 48 kHz stereo không SBR, khung 512 (dùng làm `csd-0` của MediaCodec). */
        val AAC_ELD_CONFIG: ByteArray = byteArrayOf(0xF8.toByte(), 0xE6.toByte(), 0x40, 0x00)

        fun decode(bytes: ByteArray): AudioPayload {
            val r = ByteReader(bytes)
            val rawCodec = r.u8()
            val codec = AudioCodec.of(rawCodec) ?: wireError(WireErrorCode.invalidField, "audio.codec")
            val hold = r.u16()
            return AudioPayload(codec, hold, r.take(r.remaining)).also { it.validate() }
        }
    }
}
