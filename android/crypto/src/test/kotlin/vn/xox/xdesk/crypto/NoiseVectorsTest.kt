package vn.xox.xdesk.crypto

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import vn.xox.xdesk.testing.Vectors
import vn.xox.xdesk.testing.hex
import vn.xox.xdesk.testing.list
import vn.xox.xdesk.testing.str
import vn.xox.xdesk.testing.strings
import vn.xox.xdesk.wire.Hex

/** Chạy 3 vector cacophony công khai: từng message bắt tay, handshake hash, message truyền tải. */
class NoiseVectorsTest {
    private fun errorOf(block: () -> Unit) = assertFailsWith<CryptoException> { block() }.code

    private fun runVector(file: String, pattern: NoisePattern) {
        val v = Vectors.load(file).list("vectors").single()
        assertEquals(pattern.protocolName, v.str("protocol_name"))
        val initPsk = (v["init_psks"] as? vn.xox.xdesk.wire.json.JsonArray)?.let { v.strings("init_psks").single() }
        val respPsk = (v["resp_psks"] as? vn.xox.xdesk.wire.json.JsonArray)?.let { v.strings("resp_psks").single() }
        val initiator = NoiseHandshakeState(
            pattern, NoiseRole.INITIATOR, v.hex("init_static"), v["init_remote_static"]?.let { v.hex("init_remote_static") },
            initPsk?.let(Hex::decode), v.hex("init_prologue"), v.hex("init_ephemeral"), true,
        )
        val responder = NoiseHandshakeState(
            pattern, NoiseRole.RESPONDER, v.hex("resp_static"), null, respPsk?.let(Hex::decode),
            v.hex("resp_prologue"), v.hex("resp_ephemeral"), true,
        )
        val messages = v.list("messages")
        for (i in 0 until pattern.messageCount) {
            val (writer, reader) = if (i % 2 == 0) initiator to responder else responder to initiator
            val payload = messages[i].hex("payload")
            val wire = writer.writeMessage(payload)
            assertContentEquals(messages[i].hex("ciphertext"), wire, "message $i")
            assertContentEquals(payload, reader.readMessage(wire), "message $i payload")
        }
        assertTrue(initiator.isComplete && responder.isComplete)
        assertContentEquals(v.hex("handshake_hash"), initiator.handshakeHash)
        assertContentEquals(v.hex("handshake_hash"), responder.handshakeHash)

        val (i2r, r2i) = initiator.splitKeys()
        assertContentEquals(i2r, responder.splitKeys().first)
        val send = NoiseCipherState(i2r)
        val recv = NoiseCipherState(r2i)
        for (i in pattern.messageCount until messages.size) {
            val state = if (i % 2 == 0) send else recv
            val ciphertext = state.encrypt(ByteArray(0), messages[i].hex("payload"))
            assertContentEquals(messages[i].hex("ciphertext"), ciphertext, "transport $i")
        }
    }

    @Test fun xx() = runVector("noise-xx.json", NoisePattern.XX)

    @Test fun xxPsk3() = runVector("noise-xxpsk3.json", NoisePattern.XX_PSK3)

    @Test fun ik() = runVector("noise-ik.json", NoisePattern.IK)

    private fun pair(pattern: NoisePattern, psk: ByteArray? = null): Pair<NoiseHandshakeState, NoiseHandshakeState> {
        val i = DeviceIdentity.generate()
        val r = DeviceIdentity.generate()
        val remote = if (pattern == NoisePattern.IK) r.publicKey else null
        return NoiseHandshakeState(pattern, NoiseRole.INITIATOR, i.privateKey(), remote, psk) to
            NoiseHandshakeState(pattern, NoiseRole.RESPONDER, r.privateKey(), null, psk)
    }

    @Test
    fun firstMessagePayloadMustBeEmptyForXxAndXxPsk3() {
        for (pattern in listOf(NoisePattern.XX, NoisePattern.XX_PSK3)) {
            val (i, r) = pair(pattern, if (pattern.usesPresharedKey) ByteArray(32) { 1 } else null)
            assertEquals(CryptoErrorCode.invalidHandshakePayload, errorOf { i.writeMessage(byteArrayOf(1)) })
            val clear = i.writeMessage()
            // Bên đọc cũng từ chối: thay bằng message 0 có payload nối thêm (không mã hoá ở message 0).
            // XX: payload rõ bị bác bằng invalidHandshakePayload; XXpsk3: `e` đã mix khoá nên cũng bị bác (không xác thực được).
            val readError = errorOf { r.readMessage(clear + byteArrayOf(9)) }
            assertTrue(readError in setOf(CryptoErrorCode.invalidHandshakePayload, CryptoErrorCode.authenticationFailed), "$pattern: $readError")
            assertEquals(0, r.readMessage(clear).size)
        }
    }

    @Test
    fun allZeroDiffieHellmanIsRejected() {
        val (_, r) = pair(NoisePattern.XX)
        r.readMessage(ByteArray(32)) // e = điểm bậc thấp u=0
        assertEquals(CryptoErrorCode.invalidDiffieHellman, errorOf { r.writeMessage() })
        assertEquals(CryptoErrorCode.invalidDiffieHellman, errorOf { Primitives.x25519(ByteArray(32) { 3 }, ByteArray(32)) })
    }

    @Test
    fun failedReadLeavesStateUsable() {
        val (i, r) = pair(NoisePattern.IK)
        val m0 = i.writeMessage(byteArrayOf(5))
        val tampered = m0.copyOf().also { it[it.size - 1] = (it[it.size - 1].toInt() xor 1).toByte() }
        assertEquals(CryptoErrorCode.authenticationFailed, errorOf { r.readMessage(tampered) })
        assertContentEquals(byteArrayOf(5), r.readMessage(m0))
    }

    @Test
    fun misuseIsReported() {
        val (i, r) = pair(NoisePattern.XX)
        assertEquals(CryptoErrorCode.wrongTurn, errorOf { r.writeMessage() })
        assertEquals(CryptoErrorCode.handshakeIncomplete, errorOf { i.splitKeys() })
        assertEquals(CryptoErrorCode.messageTooShort, errorOf { r.readMessage(ByteArray(5)) })
        assertEquals(CryptoErrorCode.missingPresharedKey, errorOf {
            NoiseHandshakeState(NoisePattern.XX_PSK3, NoiseRole.INITIATOR, ByteArray(32) { 1 })
        })
        assertEquals(CryptoErrorCode.missingRemoteStaticKey, errorOf {
            NoiseHandshakeState(NoisePattern.IK, NoiseRole.INITIATOR, ByteArray(32) { 1 })
        })
    }
}
