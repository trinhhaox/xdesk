package vn.xox.xdesk.wire

/** Ghi số nguyên big-endian. u8/u16 là `Int`, u32 là `Long`. */
class ByteWriter(capacity: Int = 32) {
    private var buffer = ByteArray(maxOf(capacity, 8))
    var size = 0
        private set

    private fun ensure(extra: Int) {
        if (size + extra > buffer.size) buffer = buffer.copyOf(maxOf(buffer.size * 2, size + extra))
    }

    fun u8(value: Int) { ensure(1); buffer[size++] = value.toByte() }

    fun u16(value: Int) { u8(value ushr 8); u8(value) }

    fun u32(value: Long) { u16((value ushr 16).toInt()); u16(value.toInt()) }

    fun f32(value: Float) = u32(value.toRawBits().toLong() and 0xFFFFFFFFL)

    fun append(bytes: ByteArray) {
        ensure(bytes.size)
        bytes.copyInto(buffer, size)
        size += bytes.size
    }

    fun toByteArray(): ByteArray = buffer.copyOf(size)
}

/** Đọc số nguyên big-endian; thiếu dữ liệu → `truncated`. */
class ByteReader(private val bytes: ByteArray, private var position: Int = 0) {
    val remaining: Int get() = bytes.size - position

    private fun need(count: Int) {
        if (remaining < count) wireError(WireErrorCode.truncated, "need $count, have $remaining")
    }

    fun u8(): Int { need(1); return bytes[position++].toInt() and 0xFF }

    fun u16(): Int = (u8() shl 8) or u8()

    fun u32(): Long = (u16().toLong() shl 16) or u16().toLong()

    fun f32(): Float = Float.fromBits(u32().toInt())

    fun take(count: Int): ByteArray {
        need(count)
        return bytes.copyOfRange(position, position + count).also { position += count }
    }
}

/** Hex thường, dùng cho test vectors và log chẩn đoán. */
object Hex {
    private const val DIGITS = "0123456789abcdef"

    fun encode(bytes: ByteArray): String = buildString(bytes.size * 2) {
        for (b in bytes) {
            append(DIGITS[(b.toInt() shr 4) and 0xF])
            append(DIGITS[b.toInt() and 0xF])
        }
    }

    fun decode(text: String): ByteArray {
        require(text.length % 2 == 0) { "hex length must be even" }
        return ByteArray(text.length / 2) { i ->
            val hi = Character.digit(text[2 * i], 16)
            val lo = Character.digit(text[2 * i + 1], 16)
            require(hi >= 0 && lo >= 0) { "invalid hex digit" }
            ((hi shl 4) or lo).toByte()
        }
    }
}
