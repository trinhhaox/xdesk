package vn.xox.xdesk.crypto

import java.security.GeneralSecurityException
import java.security.KeyFactory
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.KeyAgreement

/**
 * X25519 qua JCA "XDH" bằng khoá mã hoá DER (PKCS#8 / X.509, RFC 8410) thay vì XECPrivateKeySpec:
 * Conscrypt trên Android (máy thật API 33, JP1) không nhận XEC*KeySpec nhưng nhận dạng DER, JDK 11+ nhận cả hai.
 * Trước lần dùng đầu, [available] tự kiểm bằng vector RFC 7748 §6.1; provider nào trả sai hoặc ném lỗi
 * thì dùng [X25519Fallback] cho cả phiên chạy, không bao giờ tin một kết quả chưa được kiểm.
 */
internal object X25519Jca {
    private val pkcs8Prefix = hex("302e020100300506032b656e04220420")
    private val x509Prefix = hex("302a300506032b656e032100")

    val available: Boolean by lazy { selfTest() }

    /** u-coordinate ở dạng 32 byte little-endian như RFC 7748; ném [GeneralSecurityException] nếu provider từ chối. */
    fun agree(privateKey: ByteArray, publicKey: ByteArray): ByteArray {
        val factory = KeyFactory.getInstance("XDH")
        val agreement = KeyAgreement.getInstance("XDH")
        agreement.init(factory.generatePrivate(PKCS8EncodedKeySpec(pkcs8Prefix + privateKey)))
        agreement.doPhase(factory.generatePublic(X509EncodedKeySpec(x509Prefix + publicKey)), true)
        return agreement.generateSecret()
    }

    private fun selfTest(): Boolean = try {
        val alice = hex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
        val bobPublic = hex("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
        val shared = hex("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742")
        val alicePublic = hex("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
        agree(alice, bobPublic).contentEquals(shared) && agree(alice, basePoint()).contentEquals(alicePublic)
    } catch (e: GeneralSecurityException) {
        false
    } catch (e: LinkageError) {
        false
    }

    private fun basePoint() = ByteArray(Primitives.KEY_LENGTH).also { it[0] = 9 }

    private fun hex(s: String) = ByteArray(s.length / 2) { s.substring(2 * it, 2 * it + 2).toInt(16).toByte() }
}
