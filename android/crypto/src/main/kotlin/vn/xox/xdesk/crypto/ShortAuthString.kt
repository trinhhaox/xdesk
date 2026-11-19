package vn.xox.xdesk.crypto

import java.security.MessageDigest

/** Mã so khớp 6 số (SAS) có cam kết chống MITM mài khoá, chỉ cho XX. Thiết kế: `crypto-handshake.md` §5. */
object ShortAuthString {
    const val NONCE_LENGTH = 16
    const val COMMITMENT_LENGTH = 32
    private val commitLabel = "xdesk v1 sas-commit".toByteArray()
    private val codeLabel = "xdesk v1 sas".toByteArray()

    fun randomNonce(): ByteArray = Primitives.randomBytes(NONCE_LENGTH)

    /** `SHA-256("xdesk v1 sas-commit" | e.pub | s.pub | nonce)` của initiator, gửi trước message 1. */
    fun commitment(ephemeralKey: ByteArray, staticKey: ByteArray, nonce: ByteArray): ByteArray {
        if (ephemeralKey.size != 32 || staticKey.size != 32 || nonce.size != NONCE_LENGTH) cryptoError(CryptoErrorCode.invalidLength)
        return Primitives.sha256(commitLabel, ephemeralKey, staticKey, nonce)
    }

    /** Responder kiểm sau message 3; so sánh thời gian hằng. */
    fun verify(commitment: ByteArray, ephemeralKey: ByteArray, staticKey: ByteArray, nonce: ByteArray): Boolean =
        MessageDigest.isEqual(commitment, commitment(ephemeralKey, staticKey, nonce))

    /**
     * Mã 0…999 999 = `u64 BE(HKDF-SHA256(ikm = nonce, salt = messageTwoHash, info = "xdesk v1 sas", 8 B)) mod 10^6`.
     * `messageTwoHash` là hash ngay sau message 2 (`NoiseHandshakeState.messageTwoHash`), KHÔNG phải hash cuối.
     */
    fun code(messageTwoHash: ByteArray, nonce: ByteArray): Int {
        if (messageTwoHash.size != 32 || nonce.size != NONCE_LENGTH) cryptoError(CryptoErrorCode.invalidLength)
        val bytes = Primitives.hkdf(nonce, messageTwoHash, codeLabel, 8)
        var value = java.math.BigInteger(1, bytes)
        value = value.mod(java.math.BigInteger.valueOf(1_000_000))
        return value.toInt()
    }

    /** Hiển thị "123 456" (đủ 6 chữ số, đệm 0 đầu). */
    fun format(code: Int): String {
        val text = "%06d".format(Math.floorMod(code, 1_000_000))
        return "${text.substring(0, 3)} ${text.substring(3)}"
    }
}
