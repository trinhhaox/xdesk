package vn.xox.xdesk.crypto

import java.math.BigInteger
import java.security.GeneralSecurityException
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.NoSuchAlgorithmException
import java.security.SecureRandom
import java.security.spec.NamedParameterSpec
import java.security.spec.XECPrivateKeySpec
import java.security.spec.XECPublicKeySpec
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Primitive qua JCA (không thư viện ngoài): XDH (API 33+, nếu không có thì [X25519Fallback]), ChaCha20-Poly1305, SHA-256, HmacSHA256. */
internal object Primitives {
    const val KEY_LENGTH = 32
    const val TAG_LENGTH = 16
    private val random = SecureRandom()
    private val basePoint = ByteArray(KEY_LENGTH).also { it[0] = 9 }

    fun randomBytes(count: Int): ByteArray = ByteArray(count).also(random::nextBytes)

    fun sha256(vararg parts: ByteArray): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        parts.forEach(digest::update)
        return digest.digest()
    }

    fun hmac(key: ByteArray, vararg parts: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        // HMAC với khoá rỗng ≡ khoá 32 byte 0 (khoá được đệm 0 tới cỡ block); SecretKeySpec cấm khoá rỗng.
        mac.init(SecretKeySpec(if (key.isEmpty()) ByteArray(KEY_LENGTH) else key, "HmacSHA256"))
        parts.forEach(mac::update)
        return mac.doFinal()
    }

    /** HKDF của Noise (rev 34 §4.3): `outputs` khối 32 byte nối tiếp với byte đếm 1, 2, 3. */
    fun noiseHkdf(chainingKey: ByteArray, input: ByteArray, outputs: Int): List<ByteArray> {
        val temp = hmac(chainingKey, input)
        var previous = ByteArray(0)
        return List(outputs) { i ->
            previous = hmac(temp, previous, byteArrayOf((i + 1).toByte()))
            previous
        }
    }

    /** HKDF-SHA256 chuẩn RFC 5869 (extract + expand), dùng cho khoá phiên, rekey và SAS. */
    fun hkdf(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        val prk = hmac(salt, ikm)
        val out = ByteArray(length)
        var previous = ByteArray(0)
        var offset = 0
        var counter = 1
        while (offset < length) {
            previous = hmac(prk, previous, info, byteArrayOf(counter++.toByte()))
            val n = minOf(previous.size, length - offset)
            previous.copyInto(out, offset, 0, n)
            offset += n
        }
        return out
    }

    fun nonce(counter: Long): ByteArray {
        val n = ByteArray(12)
        for (i in 0 until 8) n[4 + i] = (counter ushr (8 * i)).toByte()
        return n
    }

    /** Trả `ciphertext | tag`. Mỗi lần gọi một Cipher mới nên không dính cơ chế chống tái dùng IV của JDK. */
    fun seal(key: ByteArray, counter: Long, ad: ByteArray, plaintext: ByteArray): ByteArray = try {
        val cipher = newAead()
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "ChaCha20"), IvParameterSpec(nonce(counter)))
        cipher.updateAAD(ad)
        cipher.doFinal(plaintext)
    } catch (e: GeneralSecurityException) {
        cryptoError(CryptoErrorCode.invalidKeyLength)
    }

    fun open(key: ByteArray, counter: Long, ad: ByteArray, sealed: ByteArray): ByteArray {
        if (sealed.size < TAG_LENGTH) cryptoError(CryptoErrorCode.messageTooShort)
        return try {
            val cipher = newAead()
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "ChaCha20"), IvParameterSpec(nonce(counter)))
            cipher.updateAAD(ad)
            cipher.doFinal(sealed)
        } catch (e: AEADBadTagException) {
            cryptoError(CryptoErrorCode.authenticationFailed)
        } catch (e: GeneralSecurityException) {
            cryptoError(CryptoErrorCode.authenticationFailed)
        }
    }

    /** Tên chuẩn JDK; Android (API 28+) đăng ký là "ChaCha20/Poly1305/NoPadding". */
    private fun newAead(): Cipher = try {
        Cipher.getInstance("ChaCha20-Poly1305")
    } catch (e: NoSuchAlgorithmException) {
        Cipher.getInstance("ChaCha20/Poly1305/NoPadding")
    }

    fun x25519PublicKey(privateKey: ByteArray): ByteArray = agree(privateKey, basePoint)

    /** DH X25519. Kết quả toàn số 0 (điểm bậc thấp) bị từ chối tường minh, bất kể provider có tự ném hay không. */
    fun x25519(privateKey: ByteArray, publicKey: ByteArray): ByteArray {
        val secret = agree(privateKey, publicKey)
        if (MessageDigest.isEqual(secret, ByteArray(KEY_LENGTH))) cryptoError(CryptoErrorCode.invalidDiffieHellman)
        return secret
    }

    /** `-Dxdesk.x25519.fallback=true` ép dùng bản thuần Kotlin (chạy cả bộ vector trên JVM có XDH). */
    @Volatile internal var preferJca = System.getProperty("xdesk.x25519.fallback") != "true"

    private fun agree(privateKey: ByteArray, publicKey: ByteArray): ByteArray {
        if (privateKey.size != KEY_LENGTH) cryptoError(CryptoErrorCode.invalidKeyLength)
        if (publicKey.size != KEY_LENGTH) cryptoError(CryptoErrorCode.invalidPublicKey)
        if (preferJca) {
            try {
                return agreeJca(privateKey, publicKey)
            } catch (e: NoSuchAlgorithmException) {
                preferJca = false
            } catch (e: LinkageError) {
                preferJca = false // API < 33: thiếu XECPrivateKeySpec/NamedParameterSpec
            }
        }
        return X25519Fallback.scalarMult(privateKey, publicKey)
    }

    private fun agreeJca(privateKey: ByteArray, publicKey: ByteArray): ByteArray {
        return try {
            val params = NamedParameterSpec.X25519
            val factory = KeyFactory.getInstance("XDH")
            val little = publicKey.reversedArray()
            little[0] = (little[0].toInt() and 0x7F).toByte() // RFC 7748: bỏ bit cao của u
            val agreement = KeyAgreement.getInstance("XDH")
            agreement.init(factory.generatePrivate(XECPrivateKeySpec(params, privateKey)))
            agreement.doPhase(factory.generatePublic(XECPublicKeySpec(params, BigInteger(1, little))), true)
            agreement.generateSecret().also { if (it.size != KEY_LENGTH) cryptoError(CryptoErrorCode.invalidDiffieHellman) }
        } catch (e: NoSuchAlgorithmException) {
            throw e
        } catch (e: GeneralSecurityException) {
            cryptoError(CryptoErrorCode.invalidDiffieHellman)
        }
    }
}
