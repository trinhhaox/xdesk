package vn.xox.xdesk.wire

/** Loại frame trên kênh điều khiển TCP. */
enum class ControlFrameKind(val raw: Int) {
    HANDSHAKE(0x01), CONTROL(0x02), BULK(0x03), MEDIA_OVER_TCP(0x04);

    companion object {
        fun of(raw: Int): ControlFrameKind? = entries.firstOrNull { it.raw == raw }
    }
}

/** Một frame điều khiển: `u32 len | u8 kind | payload[len-1]`, `len` gồm cả byte kind. */
class ControlFrame(val kind: ControlFrameKind, val payload: ByteArray) {
    override fun equals(other: Any?): Boolean =
        other is ControlFrame && kind == other.kind && payload.contentEquals(other.payload)

    override fun hashCode(): Int = 31 * kind.hashCode() + payload.contentHashCode()

    override fun toString(): String = "ControlFrame($kind, ${payload.size} B)"

    internal fun validate(extraBulkAllowance: Int) {
        if (payload.size + 1 > MAX_LENGTH) wireError(WireErrorCode.frameTooLarge, "${payload.size + 1}")
        if (kind == ControlFrameKind.BULK && payload.size > MAX_BULK_PAYLOAD + extraBulkAllowance) {
            wireError(WireErrorCode.payloadTooLarge, "${payload.size}")
        }
    }

    companion object {
        const val MAX_LENGTH = 1 shl 20
        const val MAX_BULK_PAYLOAD = 64 * 1024
    }
}

/** Frame đã giải mã kèm số byte đã dùng trong bộ đệm. */
class DecodedFrame(val frame: ControlFrame, val consumed: Int)

object ControlFrameCodec {
    /** `extraBulkAllowance` = 16 khi kênh đã mã hoá (tag AEAD cộng vào payload bulk). */
    fun encode(frame: ControlFrame, extraBulkAllowance: Int = 0): ByteArray {
        frame.validate(extraBulkAllowance)
        val w = ByteWriter(frame.payload.size + 5)
        w.u32(frame.payload.size + 1L)
        w.u8(frame.kind.raw)
        w.append(frame.payload)
        return w.toByteArray()
    }

    /**
     * Giải mã một frame ở `offset` của `bytes[0 until end]`. Trả `null` khi chưa đủ dữ liệu.
     * `len` sai bị báo ngay khi đủ 4 byte đầu, không chờ hết payload.
     */
    fun decode(bytes: ByteArray, offset: Int = 0, end: Int = bytes.size, extraBulkAllowance: Int = 0): DecodedFrame? {
        val available = end - offset
        if (available < 4) return null
        val head = ByteReader(bytes.copyOfRange(offset, offset + minOf(available, 5)))
        val len = checkedLength(head.u32())
        if (available < 5) return null
        val rawKind = head.u8()
        val kind = ControlFrameKind.of(rawKind) ?: wireError(WireErrorCode.unknownFrameKind, "$rawKind")
        if (available - 5 < len - 1) return null
        val frame = ControlFrame(kind, bytes.copyOfRange(offset + 5, offset + 4 + len))
        frame.validate(extraBulkAllowance)
        return DecodedFrame(frame, 4 + len)
    }

    private fun checkedLength(len: Long): Int {
        if (len < 1) wireError(WireErrorCode.invalidFrameLength, "$len")
        if (len > ControlFrame.MAX_LENGTH) wireError(WireErrorCode.frameTooLarge, "$len")
        return len.toInt()
    }
}

/** Bộ giải mã luồng TCP. Sau khi `next()` ném lỗi, kết nối phải bị đóng. */
class ControlFrameDecoder {
    private var buffer = ByteArray(1024)
    private var start = 0
    private var end = 0

    /** Đặt 16 khi kênh đã mã hoá. */
    var extraBulkAllowance = 0

    val bufferedCount: Int get() = end - start

    fun append(bytes: ByteArray) {
        if (end + bytes.size > buffer.size) {
            val live = end - start
            val target = if (live + bytes.size <= buffer.size) buffer else ByteArray(maxOf(buffer.size * 2, live + bytes.size))
            buffer.copyInto(target, 0, start, end)
            buffer = target
            start = 0
            end = live
        }
        bytes.copyInto(buffer, end)
        end += bytes.size
    }

    fun next(): ControlFrame? {
        val decoded = ControlFrameCodec.decode(buffer, start, end, extraBulkAllowance) ?: return null
        start += decoded.consumed
        if (start == end) { start = 0; end = 0 }
        return decoded.frame
    }
}
