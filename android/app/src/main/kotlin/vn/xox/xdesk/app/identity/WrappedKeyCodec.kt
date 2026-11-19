package vn.xox.xdesk.app.identity

import java.security.GeneralSecurityException
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Khoá riêng của danh tính không còn đọc được (Keystore mất khoá hoặc tệp hỏng). Không tự tạo lại: sẽ làm mất mọi ghép đôi. */
class IdentityUnavailableException(cause: Throwable) : RuntimeException("Danh tính thiết bị không đọc được", cause)

/**
 * Bọc/mở khoá riêng X25519 bằng một khoá AES-GCM (thực tế là khoá nằm trong Android Keystore, không xuất ra được).
 * Định dạng tệp: `u8 version=1 | iv 12 B | ciphertext | tag 16 B`; AD cố định để tệp không đổi chỗ sang ngữ cảnh khác.
 */
internal object WrappedKeyCodec {
    private const val VERSION = 1
    private const val IV_LENGTH = 12
    private const val TAG_BITS = 128
    private val aad = "xdesk identity v1".toByteArray()

    /** IV do provider tự sinh (khoá Keystore bắt buộc mã hoá ngẫu nhiên). */
    fun wrap(key: SecretKey, secret: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(aad)
        val ciphertext = cipher.doFinal(secret)
        check(cipher.iv.size == IV_LENGTH)
        return byteArrayOf(VERSION.toByte()) + cipher.iv + ciphertext
    }

    fun unwrap(key: SecretKey, blob: ByteArray): ByteArray {
        try {
            require(blob.size > 1 + IV_LENGTH + TAG_BITS / 8 && blob[0].toInt() == VERSION) { "định dạng tệp danh tính sai" }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, blob.copyOfRange(1, 1 + IV_LENGTH)))
            cipher.updateAAD(aad)
            return cipher.doFinal(blob, 1 + IV_LENGTH, blob.size - 1 - IV_LENGTH)
        } catch (e: GeneralSecurityException) {
            throw IdentityUnavailableException(e)
        } catch (e: IllegalArgumentException) {
            throw IdentityUnavailableException(e)
        }
    }
}
