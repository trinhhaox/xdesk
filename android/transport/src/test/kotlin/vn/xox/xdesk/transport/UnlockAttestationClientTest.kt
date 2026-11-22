package vn.xox.xdesk.transport

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertTrue
import vn.xox.xdesk.wire.Capabilities
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.UnlockAttestation

class UnlockAttestationClientTest {
    private class FakeSigner(private val outcome: Result<ByteArray>) : UnlockSigner {
        var signed: ByteArray? = null
        var hostName: String? = null
        override fun publicKey(): ByteArray = byteArrayOf(4) + ByteArray(64) { 1 }
        override fun existingPublicKey(): ByteArray? = publicKey()
        override fun sign(message: ByteArray, hostName: String, onResult: (Result<ByteArray>) -> Unit) {
            signed = message
            this.hostName = hostName
            onResult(outcome)
        }
    }

    private val sent = mutableListOf<ControlMessage>()
    private val results = mutableListOf<ControlMessage.SystemUnlockResult>()
    private val nonce = ByteArray(32) { it.toByte() }
    private val challenge = ControlMessage.SystemUnlockChallenge(UnlockAttestation.encode(nonce), 30_000)

    private var now = 1_000L
    private val hostKey = ByteArray(32) { 0x11 }
    private val viewerKey = ByteArray(32) { 0x22 }

    private fun client(signer: UnlockSigner?) = UnlockAttestationClient(
        signer, viewerKey, { UnlockHostInfo(hostKey, "Mac của An") }, { now }, { sent += it }, { results += it },
    ).also { it.arm() }

    @Test
    fun registersKeyOnlyWhenNegotiated() {
        val c = client(FakeSigner(Result.success(ByteArray(0))))
        c.registerKey(Capabilities.REMOTE_UNLOCK)
        assertTrue(sent.isEmpty())
        c.registerKey(Capabilities.REMOTE_UNLOCK or Capabilities.UNLOCK_ATTESTATION)
        val key = assertIs<ControlMessage.UnlockKey>(sent.single())
        assertEquals(UnlockAttestation.ALGORITHM, key.alg)
    }

    @Test
    fun withoutSignerNothingIsOfferedOrSent() {
        val c = client(null)
        assertFalse(c.offered)
        c.registerKey(Capabilities.UNLOCK_ATTESTATION)
        c.answer(challenge)
        assertTrue(sent.isEmpty() && results.isEmpty())
    }

    @Test
    fun answersChallengeBySigningDomainPlusNonce() {
        val signer = FakeSigner(Result.success(ByteArray(70) { 5 }))
        client(signer).answer(challenge)
        assertContentEquals(UnlockAttestation.signedMessage(hostKey, viewerKey, nonce), signer.signed)
        assertEquals("Mac của An", signer.hostName)
        val unlock = assertIs<ControlMessage.SystemUnlock>(sent.single())
        assertEquals(UnlockAttestation.encode(ByteArray(70) { 5 }), unlock.sig)
    }

    @Test
    fun cancelledSigningReportsVietnameseResultAndSendsNothing() {
        client(FakeSigner(Result.failure(UnlockCancelledException()))).answer(challenge)
        assertTrue(sent.isEmpty())
        assertFalse(results.single().ok)
        assertEquals("Đã huỷ xác thực mở khoá Mac", results.single().message)
    }

    @Test
    fun otherSigningFailureReportsGenericMessage() {
        client(FakeSigner(Result.failure(IllegalStateException("x")))).answer(challenge)
        assertTrue(sent.isEmpty())
        assertEquals("Không xác thực được để mở khoá Mac", results.single().message)
    }

    @Test
    fun malformedNonceIsIgnored() {
        val signer = FakeSigner(Result.success(ByteArray(70)))
        client(signer).answer(ControlMessage.SystemUnlockChallenge("AAAA", 1))
        assertTrue(signer.signed == null && sent.isEmpty())
    }

    @Test
    fun unsolicitedChallengeIsDroppedAndArmIsSingleUse() {
        val signer = FakeSigner(Result.success(ByteArray(70)))
        val c = client(null.let { signer })
        c.reset()
        c.answer(challenge)
        assertTrue(signer.signed == null && sent.isEmpty())
        c.arm()
        c.answer(challenge)
        assertEquals(1, sent.size)
        c.answer(challenge)
        assertEquals(1, sent.size)
    }

    @Test
    fun armExpiresAfterThirtySeconds() {
        val signer = FakeSigner(Result.success(ByteArray(70)))
        val c = client(signer)
        now += UnlockAttestationClient.WINDOW_MS + 1
        c.answer(challenge)
        assertTrue(signer.signed == null && sent.isEmpty())
    }

    @Test
    fun invalidatedKeyReRegistersAndTellsUserToResetOnMac() {
        val c = client(FakeSigner(Result.failure(UnlockKeyInvalidatedException())))
        c.registerKey(Capabilities.UNLOCK_ATTESTATION)
        sent.clear()
        c.arm()
        c.answer(challenge)
        assertIs<ControlMessage.UnlockKey>(sent.single())
        assertTrue(results.single().message.contains("Đặt lại khoá"))
    }
}
