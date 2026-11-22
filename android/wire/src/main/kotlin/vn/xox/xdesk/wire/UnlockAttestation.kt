package vn.xox.xdesk.wire

import java.math.BigInteger
import java.security.interfaces.ECPublicKey
import java.util.Base64

/** Hằng số và định dạng dữ liệu ký cho mở khoá có chứng thực sinh trắc học (khớp `UnlockAttestation` trong Swift). */
object UnlockAttestation {
    const val ALGORITHM = "p256-ecdsa-sha256"
    const val NONCE_BYTES = 32
    const val PUBLIC_KEY_BYTES = 65
    const val CHALLENGE_TTL_MS = 30_000L
    private const val MIN_SIGNATURE_BYTES = 8
    private const val MAX_SIGNATURE_BYTES = 80
    private val DOMAIN = "xdesk v1 unlock".toByteArray(Charsets.UTF_8)

    /**
     * Dữ liệu được ký: `"xdesk v1 unlock" || hostStaticPub(32) || viewerStaticPub(32) || nonce`.
     * Gắn khoá tĩnh Noise của hai đầu để chữ ký không dùng lại được ở cặp host/viewer khác.
     */
    fun signedMessage(hostKey: ByteArray, viewerKey: ByteArray, nonce: ByteArray): ByteArray = DOMAIN + hostKey + viewerKey + nonce

    /** Dấu vân tay ngắn để đối chiếu giữa Mac và điện thoại: 8 byte đầu SHA-256, `XXXX-XXXX-XXXX-XXXX` (khớp bản Swift). */
    fun fingerprint(publicKey: ByteArray): String =
        java.security.MessageDigest.getInstance("SHA-256").digest(publicKey).take(8)
            .joinToString("") { "%02X".format(it) }.chunked(4).joinToString("-")

    fun decodeNonce(b64: String): ByteArray? = decode(b64)?.takeIf { it.size == NONCE_BYTES }

    /** X9.63 uncompressed: 65 byte, bắt đầu bằng 0x04. */
    fun decodePublicKey(b64: String): ByteArray? =
        decode(b64)?.takeIf { it.size == PUBLIC_KEY_BYTES && it[0] == 0x04.toByte() }

    /** X9.63 uncompressed (`04 || X || Y`, mỗi toạ độ đệm 32 byte) của khoá EC P-256. */
    fun encodePublicKey(key: ECPublicKey): ByteArray = byteArrayOf(0x04) + fixed32(key.w.affineX) + fixed32(key.w.affineY)

    private fun fixed32(v: BigInteger): ByteArray {
        val raw = v.toByteArray().let { if (it.size > 32) it.copyOfRange(it.size - 32, it.size) else it }
        return ByteArray(32).also { raw.copyInto(it, 32 - raw.size) }
    }

    fun encode(bytes: ByteArray): String = Base64.getEncoder().encodeToString(bytes)

    internal fun isPlausibleSignature(b64: String): Boolean = decode(b64)?.size in MIN_SIGNATURE_BYTES..MAX_SIGNATURE_BYTES

    private fun decode(b64: String): ByteArray? = try {
        Base64.getDecoder().decode(b64)
    } catch (_: IllegalArgumentException) {
        null
    }
}

internal fun ControlMessage.validateUnlockAttestation() {
    when (this) {
        is ControlMessage.SystemUnlock ->
            if (sig != null && !UnlockAttestation.isPlausibleSignature(sig)) wireError(WireErrorCode.invalidField, "system.unlock.sig")
        is ControlMessage.SystemUnlockChallenge ->
            if (UnlockAttestation.decodeNonce(nonce) == null) wireError(WireErrorCode.invalidField, "system.unlock.challenge.nonce")
        is ControlMessage.UnlockKey -> {
            if (alg != UnlockAttestation.ALGORITHM) wireError(WireErrorCode.invalidField, "unlock.key.alg")
            if (UnlockAttestation.decodePublicKey(pub) == null) wireError(WireErrorCode.invalidField, "unlock.key.pub")
        }
        else -> Unit
    }
}
