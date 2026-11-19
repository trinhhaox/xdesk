package vn.xox.xdesk.wire

enum class MediaPacketType(val raw: Int) {
    VIDEO(0x10),
    /** Để dành: giải mã được nhưng chưa có ngữ nghĩa. */
    VIDEO_PARITY(0x11),
    AUDIO(0x20),
    INPUT(0x30),
    INPUT_ACK(0x31),
    NACK(0x40),
    /** Viewer báo địa chỉ UDP cho host: payload rỗng hoặc `u64 nonce`. */
    PROBE(0x50);

    companion object {
        fun of(raw: Int): MediaPacketType? = entries.firstOrNull { it.raw == raw }
    }
}

/** Header UDP 16 byte; bit 15 của trường fragCnt trên wire là cờ keyframe. u32 là `Long`. */
data class MediaHeader(
    val type: MediaPacketType,
    val streamId: Int,
    val frameNo: Long,
    val fragIdx: Int = 0,
    val fragCnt: Int = 1,
    val isKeyframe: Boolean = false,
    val ptsMs: Long = 0,
) {
    internal fun validate() {
        if (fragCnt > MAX_FRAGMENT_COUNT) wireError(WireErrorCode.fragmentCountTooLarge, "$fragCnt")
        if (fragCnt < 1 || fragIdx >= fragCnt) wireError(WireErrorCode.invalidFragment, "idx=$fragIdx cnt=$fragCnt")
    }

    internal fun write(w: ByteWriter) {
        validate()
        w.u8(ProtocolVersion.CURRENT.major)
        w.u8(type.raw)
        w.u16(streamId)
        w.u32(frameNo)
        w.u16(fragIdx)
        w.u16(fragCnt or (if (isKeyframe) KEYFRAME_BIT else 0))
        w.u32(ptsMs)
    }

    companion object {
        const val SIZE = 16
        const val MAX_FRAGMENT_COUNT = 2048
        const val KEYFRAME_BIT = 0x8000

        internal fun read(r: ByteReader): MediaHeader {
            val ver = r.u8()
            if (ver != ProtocolVersion.CURRENT.major) wireError(WireErrorCode.unsupportedVersion, "$ver")
            val rawType = r.u8()
            val type = MediaPacketType.of(rawType) ?: wireError(WireErrorCode.unknownPacketType, "$rawType")
            val streamId = r.u16()
            val frameNo = r.u32()
            val fragIdx = r.u16()
            val rawCnt = r.u16()
            val ptsMs = r.u32()
            return MediaHeader(
                type, streamId, frameNo, fragIdx, rawCnt and KEYFRAME_BIT.inv() and 0xFFFF,
                rawCnt and KEYFRAME_BIT != 0, ptsMs,
            ).also { it.validate() }
        }
    }
}

/** Gói UDP: header + payload ≤ 1192 B (mã hoá xong ≤ 1232 B). */
class MediaPacket(val header: MediaHeader, val payload: ByteArray) {
    fun encode(): ByteArray {
        if (payload.size > MAX_PAYLOAD) wireError(WireErrorCode.payloadTooLarge, "${payload.size}")
        val w = ByteWriter(MediaHeader.SIZE + payload.size)
        header.write(w)
        w.append(payload)
        return w.toByteArray()
    }

    override fun equals(other: Any?): Boolean =
        other is MediaPacket && header == other.header && payload.contentEquals(other.payload)

    override fun hashCode(): Int = 31 * header.hashCode() + payload.contentHashCode()

    override fun toString(): String = "MediaPacket($header, ${payload.size} B)"

    companion object {
        const val MAX_PAYLOAD = 1192

        fun decode(bytes: ByteArray): MediaPacket {
            val r = ByteReader(bytes)
            val header = MediaHeader.read(r)
            if (r.remaining > MAX_PAYLOAD) wireError(WireErrorCode.payloadTooLarge, "${r.remaining}")
            return MediaPacket(header, r.take(r.remaining))
        }

        /** Gói NACK hoàn chỉnh (`fragIdx=0, fragCnt=1`, `frameNo=0`). */
        fun nack(streamId: Int, entries: List<NackEntry>) =
            MediaPacket(MediaHeader(MediaPacketType.NACK, streamId, 0), NackPayload.encode(entries))

        /** Gói `input` (1…42 sự kiện). */
        fun input(streamId: Int, events: List<InputEvent>) =
            MediaPacket(MediaHeader(MediaPacketType.INPUT, streamId, 0), InputEvent.encodeBatch(events))

        fun inputAck(streamId: Int, ack: InputAck) =
            MediaPacket(MediaHeader(MediaPacketType.INPUT_ACK, streamId, 0), ack.encode())

        /** Gói probe; `nonce` tuỳ chọn (u64 big-endian). */
        fun probe(streamId: Int, nonce: Long? = null): MediaPacket {
            val w = ByteWriter(8)
            if (nonce != null) { w.u32(nonce ushr 32); w.u32(nonce and 0xFFFFFFFFL) }
            return MediaPacket(MediaHeader(MediaPacketType.PROBE, streamId, 0), w.toByteArray())
        }
    }
}
