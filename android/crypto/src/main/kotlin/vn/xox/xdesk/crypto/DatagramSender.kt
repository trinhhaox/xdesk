package vn.xox.xdesk.crypto

/**
 * Bố cục gói UDP mã hoá: `header 16 B (rõ, là AD) | nonce u64 BE | ciphertext | tag 16 B`.
 * Nonce = `epoch u32 << 32 | counter u32`; nonce ChaCha 12 B = 4 byte 0 | nonce u64 little-endian.
 */
object DatagramFormat {
    const val HEADER_LENGTH = 16
    const val NONCE_LENGTH = 8
    const val TAG_LENGTH = 16
    const val OVERHEAD = NONCE_LENGTH + TAG_LENGTH
    const val PACKETS_PER_EPOCH = 1L shl 32
    const val REKEY_PACKET_THRESHOLD = PACKETS_PER_EPOCH - 65_536
    const val REKEY_INTERVAL_MS = 3_600_000L
}

/**
 * Phía gửi UDP. Không thread-safe. Gói gửi lại theo NACK phải gọi [seal] lại (counter mới), không gửi lại cùng byte.
 * `clock` trả mili giây đơn điệu (mặc định `System.nanoTime`).
 */
class DatagramSender(key: ByteArray, private val clock: () -> Long = { System.nanoTime() / 1_000_000 }) {
    private var key = key.copyOf()
    var epoch = 0L
        private set
    var packetsInEpoch = 0L
        private set
    private var epochStartMs = clock()

    /** `true` khi đã gửi gần 2^32 gói hoặc epoch sống ≥ 1 giờ. */
    val needsRekey: Boolean
        get() = packetsInEpoch >= DatagramFormat.REKEY_PACKET_THRESHOLD ||
            clock() - epochStartMs >= DatagramFormat.REKEY_INTERVAL_MS

    /** Chuyển sang epoch kế tiếp (khoá mới, counter về 0). */
    fun rekey() {
        if (epoch == 0xFFFFFFFFL) cryptoError(CryptoErrorCode.nonceExhausted)
        key = KeySchedule.next(key)
        epoch++
        packetsInEpoch = 0
        epochStartMs = clock()
    }

    /** Trả `header | nonce | ciphertext | tag`; `header` phải đúng 16 byte. */
    fun seal(header: ByteArray, payload: ByteArray): ByteArray {
        if (header.size != DatagramFormat.HEADER_LENGTH) cryptoError(CryptoErrorCode.invalidLength)
        if (packetsInEpoch >= DatagramFormat.PACKETS_PER_EPOCH) cryptoError(CryptoErrorCode.nonceExhausted)
        val nonce = (epoch shl 32) or packetsInEpoch
        val sealed = Primitives.seal(key, nonce, header, payload)
        packetsInEpoch++
        val out = ByteArray(header.size + DatagramFormat.NONCE_LENGTH + sealed.size)
        header.copyInto(out)
        for (i in 0 until 8) out[header.size + i] = (nonce ushr (56 - 8 * i)).toByte()
        sealed.copyInto(out, header.size + DatagramFormat.NONCE_LENGTH)
        return out
    }
}
