package vn.xox.xdesk.crypto

/**
 * Mã hoá frame TCP sau bắt tay: `len | kind | ciphertext | tag`, `len = 1 + plaintext + 16`,
 * AD = `u32 len BE | u8 kind`. Nonce = bộ đếm ngầm mỗi hướng. Frame kind 0x01 không đi qua lớp này.
 */
object StreamFormat {
    const val TAG_LENGTH = 16
    const val MAX_FRAME_LENGTH = 1_048_576

    internal fun associatedData(kind: Int, ciphertextLength: Int): ByteArray {
        val len = 1 + ciphertextLength
        return byteArrayOf((len ushr 24).toByte(), (len ushr 16).toByte(), (len ushr 8).toByte(), len.toByte(), kind.toByte())
    }
}

/** Không thread-safe; không được có hai chủ cùng bộ đếm nonce. */
class StreamSender(key: ByteArray) {
    private val state = NoiseCipherState(key.copyOf())

    /** Trả `ciphertext | tag`; người gọi đóng khung `len | kind | kết quả`. */
    fun seal(kind: Int, plaintext: ByteArray): ByteArray {
        val ciphertextLength = plaintext.size + StreamFormat.TAG_LENGTH
        if (1 + ciphertextLength > StreamFormat.MAX_FRAME_LENGTH) cryptoError(CryptoErrorCode.messageTooLarge)
        return state.encrypt(StreamFormat.associatedData(kind, ciphertextLength), plaintext)
    }

    /** Gọi ngay sau khi gửi frame control `rekey`; mọi frame sau dùng khoá mới và nonce 0. */
    fun rekey() { state.key?.let { state.initializeKey(KeySchedule.next(it)) } }
}

class StreamReceiver(key: ByteArray) {
    private val state = NoiseCipherState(key.copyOf())

    fun open(kind: Int, ciphertext: ByteArray): ByteArray {
        if (ciphertext.size < StreamFormat.TAG_LENGTH) cryptoError(CryptoErrorCode.messageTooShort)
        if (1 + ciphertext.size > StreamFormat.MAX_FRAME_LENGTH) cryptoError(CryptoErrorCode.messageTooLarge)
        return state.decrypt(StreamFormat.associatedData(kind, ciphertext.size), ciphertext)
    }

    /** Gọi ngay sau khi giải mã xong frame control `rekey`. */
    fun rekey() { state.key?.let { state.initializeKey(KeySchedule.next(it)) } }
}
