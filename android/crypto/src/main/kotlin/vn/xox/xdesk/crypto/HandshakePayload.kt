package vn.xox.xdesk.crypto

enum class DeviceRole(val raw: Int) {
    HOST(0), VIEWER(1);

    companion object { fun of(raw: Int): DeviceRole? = entries.firstOrNull { it.raw == raw } }
}

/**
 * Payload (mã hoá) của message bắt tay mang danh tính ứng dụng:
 * `u8 ver=1 | u8 role | u8 flags | u8 nameLen | name UTF-8 | [nonce 16 B nếu flags bit0]`.
 */
class HandshakePayload(val role: DeviceRole, val deviceName: String, val sasNonce: ByteArray? = null) {
    fun encode(): ByteArray {
        val name = deviceName.toByteArray(Charsets.UTF_8)
        if (name.size > MAX_NAME_LENGTH) cryptoError(CryptoErrorCode.invalidHandshakePayload)
        val nonce = sasNonce
        if (nonce != null && nonce.size != ShortAuthString.NONCE_LENGTH) cryptoError(CryptoErrorCode.invalidHandshakePayload)
        val head = byteArrayOf(VERSION.toByte(), role.raw.toByte(), (if (nonce == null) 0 else HAS_SAS_NONCE).toByte(), name.size.toByte())
        return head + name + (nonce ?: ByteArray(0))
    }

    override fun equals(other: Any?): Boolean = other is HandshakePayload && role == other.role &&
        deviceName == other.deviceName && sasNonce.contentEquals(other.sasNonce)

    override fun hashCode(): Int = 31 * (31 * role.hashCode() + deviceName.hashCode()) + sasNonce.contentHashCode()

    companion object {
        const val VERSION = 1
        const val MAX_NAME_LENGTH = 64
        private const val HAS_SAS_NONCE = 0x01

        fun decode(bytes: ByteArray): HandshakePayload {
            fun invalid(): Nothing = cryptoError(CryptoErrorCode.invalidHandshakePayload)
            if (bytes.size < 4 || (bytes[0].toInt() and 0xFF) != VERSION) invalid()
            val flags = bytes[2].toInt() and 0xFF
            if (flags and HAS_SAS_NONCE.inv() != 0) invalid()
            val role = DeviceRole.of(bytes[1].toInt() and 0xFF) ?: invalid()
            val nameLength = bytes[3].toInt() and 0xFF
            val hasNonce = flags and HAS_SAS_NONCE != 0
            val expected = 4 + nameLength + if (hasNonce) ShortAuthString.NONCE_LENGTH else 0
            if (nameLength > MAX_NAME_LENGTH || bytes.size != expected) invalid()
            val name = try {
                Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes, 4, nameLength)).toString()
            } catch (e: java.nio.charset.CharacterCodingException) {
                invalid()
            }
            return HandshakePayload(role, name, if (hasNonce) bytes.copyOfRange(4 + nameLength, bytes.size) else null)
        }
    }
}
