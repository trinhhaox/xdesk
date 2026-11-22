package vn.xox.xdesk.wire

import java.math.BigInteger
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.PublicKey
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import vn.xox.xdesk.testing.Vectors
import vn.xox.xdesk.testing.obj
import vn.xox.xdesk.testing.str

/** Mở khoá có chứng thực: codec 3 message + bố cục dữ liệu ký/DER khớp bản Swift (vector do CryptoKit sinh). */
class UnlockAttestationTest {
    private val params: ECParameterSpec = AlgorithmParameters.getInstance("EC").run {
        init(ECGenParameterSpec("secp256r1"))
        getParameterSpec(ECParameterSpec::class.java)
    }

    private fun publicKeyFromX963(raw: ByteArray): PublicKey {
        require(raw.size == 65 && raw[0] == 4.toByte())
        val x = BigInteger(1, raw.copyOfRange(1, 33))
        val y = BigInteger(1, raw.copyOfRange(33, 65))
        return KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(ECPoint(x, y), params))
    }

    private fun verify(pub: PublicKey, message: ByteArray, der: ByteArray): Boolean =
        Signature.getInstance("SHA256withECDSA").run {
            initVerify(pub)
            update(message)
            try { verify(der) } catch (_: java.security.SignatureException) { false }
        }

    private fun b64(vector: vn.xox.xdesk.wire.json.JsonObject, key: String) = java.util.Base64.getDecoder().decode(vector.str(key))
    private fun host(v: vn.xox.xdesk.wire.json.JsonObject) = b64(v, "hostKey")
    private fun viewer(v: vn.xox.xdesk.wire.json.JsonObject) = b64(v, "viewerKey")
    private fun vectorMessage(v: vn.xox.xdesk.wire.json.JsonObject, nonce: ByteArray) = UnlockAttestation.signedMessage(host(v), viewer(v), nonce)

    @Test
    fun swiftGeneratedSignatureVerifiesOnJvm() {
        val vector = Vectors.load("control-frames.json").obj("unlockAttestation")
        val pub = checkNotNull(UnlockAttestation.decodePublicKey(vector.str("publicKey")))
        val nonce = checkNotNull(UnlockAttestation.decodeNonce(vector.str("nonce")))
        val sig = java.util.Base64.getDecoder().decode(vector.str("signature"))
        assertEquals(vector.str("domain"), "xdesk v1 unlock")
        assertTrue(verify(publicKeyFromX963(pub), vectorMessage(vector, nonce), sig))
    }

    @Test
    fun swiftSignatureFailsForOtherNonceOrMissingDomain() {
        val vector = Vectors.load("control-frames.json").obj("unlockAttestation")
        val pub = publicKeyFromX963(checkNotNull(UnlockAttestation.decodePublicKey(vector.str("publicKey"))))
        val nonce = checkNotNull(UnlockAttestation.decodeNonce(vector.str("nonce")))
        val sig = java.util.Base64.getDecoder().decode(vector.str("signature"))
        assertFalse(verify(pub, UnlockAttestation.signedMessage(host(vector), viewer(vector), ByteArray(32) { 9 }), sig))
        assertFalse(verify(pub, UnlockAttestation.signedMessage(ByteArray(32) { 9 }, viewer(vector), nonce), sig), "khác host")
        assertFalse(verify(pub, UnlockAttestation.signedMessage(host(vector), ByteArray(32) { 9 }, nonce), sig), "khác viewer")
        assertFalse(verify(pub, nonce, sig))
    }

    @Test
    fun softwareKeySignatureUsesTheSameLayoutAndPublicKeyEncoding() {
        val pair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        val nonce = ByteArray(32) { it.toByte() }
        val der = Signature.getInstance("SHA256withECDSA").run {
            initSign(pair.private)
            update(UnlockAttestation.signedMessage(ByteArray(32) { 1 }, ByteArray(32) { 2 }, nonce))
            sign()
        }
        val raw = UnlockAttestation.encodePublicKey(pair.public as ECPublicKey)
        assertEquals(65, raw.size)
        assertNotNull(UnlockAttestation.decodePublicKey(UnlockAttestation.encode(raw)))
        assertTrue(verify(publicKeyFromX963(raw), UnlockAttestation.signedMessage(ByteArray(32) { 1 }, ByteArray(32) { 2 }, nonce), der))
        assertEquals(0x30, der[0].toInt())
    }

    @Test
    fun signedMessageIsDomainThenHostViewerNonce() {
        val nonce = ByteArray(32) { 7 }
        val host = ByteArray(32) { 1 }
        val viewer = ByteArray(32) { 2 }
        assertContentEquals("xdesk v1 unlock".toByteArray() + host + viewer + nonce, UnlockAttestation.signedMessage(host, viewer, nonce))
    }

    @Test
    fun fingerprintFormatMatchesSwift() {
        val f = UnlockAttestation.fingerprint(ByteArray(65) { 4 })
        assertEquals(19, f.length)
        assertEquals(4, f.split("-").size)
        assertTrue(f.all { it == '-' || it in '0'..'9' || it in 'A'..'F' })
    }

    @Test
    fun messagesRoundTrip() {
        val pub = UnlockAttestation.encode(byteArrayOf(4) + ByteArray(64) { 1 })
        val nonce = UnlockAttestation.encode(ByteArray(32) { 2 })
        val cases = listOf(
            ControlMessage.UnlockKey(UnlockAttestation.ALGORITHM, pub),
            ControlMessage.SystemUnlockChallenge(nonce, 30_000),
            ControlMessage.SystemUnlock(sig = UnlockAttestation.encode(ByteArray(70) { 3 })),
            ControlMessage.SystemUnlock(),
            ControlMessage.SystemUnlock(token = "t"),
            ControlMessage.SystemLockResult(false, "Mac chỉ tắt màn hình"),
        )
        for (message in cases) {
            val bytes = ControlMessageCodec.encode(ControlEnvelope(5, message))
            assertEquals(ControlEnvelope(5, message), ControlMessageCodec.decode(bytes))
        }
    }

    @Test
    fun malformedFieldsAreRejected() {
        fun decode(json: String) = ControlMessageCodec.decode(json.toByteArray())
        assertFailsWith<WireException> { decode("""{"alg":"rsa","id":1,"pub":"AAAA","t":"unlock.key"}""") }
        assertFailsWith<WireException> { decode("""{"id":1,"nonce":"AAAA","t":"system.unlock.challenge","ttlMs":1}""") }
        assertFailsWith<WireException> { decode("""{"id":1,"sig":"!!!","t":"system.unlock"}""") }
    }
}
