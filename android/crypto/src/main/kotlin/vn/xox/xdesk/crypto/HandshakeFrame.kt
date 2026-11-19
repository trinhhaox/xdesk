package vn.xox.xdesk.crypto

/**
 * Nội dung frame TCP kind 0x01: `u8 type | body`.
 * `begin` (0x00): `u8 wireMajor=1 | u8 pattern`; `commit` (0x01): 32 B cam kết SAS (chỉ XX); `noise` (0x02): một message Noise.
 */
sealed interface HandshakeFrame {
    data class Begin(val pattern: NoisePattern) : HandshakeFrame
    class Commit(val commitment: ByteArray) : HandshakeFrame
    class Noise(val message: ByteArray) : HandshakeFrame

    fun encode(): ByteArray = when (this) {
        is Begin -> byteArrayOf(0x00, WIRE_MAJOR.toByte(), pattern.raw.toByte())
        is Commit -> byteArrayOf(0x01) + commitment
        is Noise -> byteArrayOf(0x02) + message
    }

    companion object {
        const val WIRE_MAJOR = 1

        fun decode(bytes: ByteArray): HandshakeFrame {
            fun invalid(): Nothing = cryptoError(CryptoErrorCode.invalidHandshakeFrame)
            if (bytes.isEmpty()) invalid()
            val body = bytes.copyOfRange(1, bytes.size)
            return when (bytes[0].toInt()) {
                0x00 -> {
                    if (body.size != 2 || body[0].toInt() != WIRE_MAJOR) invalid()
                    Begin(NoisePattern.of(body[1].toInt() and 0xFF) ?: invalid())
                }
                0x01 -> if (body.size == ShortAuthString.COMMITMENT_LENGTH) Commit(body) else invalid()
                0x02 -> if (body.isNotEmpty() && body.size <= NoiseHandshakeState.MAX_MESSAGE_LENGTH) Noise(body) else invalid()
                else -> invalid()
            }
        }
    }
}
