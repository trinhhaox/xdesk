package vn.xox.xdesk.crypto

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class EndToEndSessionTest {
    private fun codeOf(block: () -> Unit) = assertFailsWith<CryptoException> { block() }.code

    private fun run(pattern: NoisePattern, psk: ByteArray?, initPayload: ByteArray): Pair<NoiseHandshakeState, NoiseHandshakeState> {
        val viewer = DeviceIdentity.generate()
        val host = DeviceIdentity.generate()
        val i = NoiseHandshakeState(pattern, NoiseRole.INITIATOR, viewer.privateKey(), host.publicKey.takeIf { pattern == NoisePattern.IK }, psk)
        val r = NoiseHandshakeState(pattern, NoiseRole.RESPONDER, host.privateKey(), null, psk)
        var writer = i
        var reader = r
        for (n in 0 until pattern.messageCount) {
            val payload = if (n == 0 && pattern != NoisePattern.IK) ByteArray(0) else if (n % 2 == 0) initPayload else byteArrayOf(7)
            val received = reader.readMessage(writer.writeMessage(payload))
            assertContentEquals(payload, received)
            writer = reader.also { reader = writer }
        }
        assertContentEquals(viewer.publicKey, r.remoteStaticKey)
        assertContentEquals(host.publicKey, i.remoteStaticKey)
        return i to r
    }

    @Test
    fun allPatternsAgreeOnSessionKeysAndCarryTraffic() {
        for (pattern in NoisePattern.entries) {
            val (i, r) = run(pattern, if (pattern.usesPresharedKey) ByteArray(32) { 5 } else null, byteArrayOf(1, 2))
            val ki = i.sessionKeys()
            val kr = r.sessionKeys()
            assertContentEquals(ki.tcpSend, kr.tcpReceive)
            assertContentEquals(ki.udpReceive, kr.udpSend)
            val sender = StreamSender(ki.tcpSend)
            val receiver = StreamReceiver(kr.tcpReceive)
            for (n in 0 until 3) assertContentEquals(byteArrayOf(n.toByte()), receiver.open(2, sender.seal(2, byteArrayOf(n.toByte()))))
            val datagram = DatagramSender(ki.udpSend).seal(ByteArray(16), byteArrayOf(9))
            assertContentEquals(byteArrayOf(9), DatagramReceiver(kr.udpReceive).open(datagram).payload)
        }
    }

    @Test
    fun wrongPskFailsHandshake() {
        val a = DeviceIdentity.generate()
        val b = DeviceIdentity.generate()
        val i = NoiseHandshakeState(NoisePattern.XX_PSK3, NoiseRole.INITIATOR, a.privateKey(), null, ByteArray(32) { 1 })
        val r = NoiseHandshakeState(NoisePattern.XX_PSK3, NoiseRole.RESPONDER, b.privateKey(), null, ByteArray(32) { 2 })
        r.readMessage(i.writeMessage())
        i.readMessage(r.writeMessage())
        val third = i.writeMessage()
        assertEquals(CryptoErrorCode.authenticationFailed, codeOf { r.readMessage(third) })
    }

    @Test
    fun sasCodeUsesMessageTwoHashAndIgnoresMessageThreePayload() {
        fun sasRun(name: String): Pair<Int, Int> {
            val viewer = DeviceIdentity.generate()
            val i = NoiseHandshakeState(NoisePattern.XX, NoiseRole.INITIATOR, viewer.privateKey())
            val r = NoiseHandshakeState(NoisePattern.XX, NoiseRole.RESPONDER, DeviceIdentity.generate().privateKey())
            val nonce = ShortAuthString.randomNonce()
            val m0 = i.writeMessage()
            val commitment = ShortAuthString.commitment(checkNotNull(i.localEphemeralKey), viewer.publicKey, nonce)
            r.readMessage(m0)
            i.readMessage(r.writeMessage(HandshakePayload(DeviceRole.HOST, "Mac").encode()))
            assertContentEquals(i.messageTwoHash, r.messageTwoHash)
            val m3 = i.writeMessage(HandshakePayload(DeviceRole.VIEWER, name, nonce).encode())
            val hello = HandshakePayload.decode(r.readMessage(m3))
            assertTrue(ShortAuthString.verify(commitment, checkNotNull(r.remoteEphemeralKey), checkNotNull(r.remoteStaticKey), checkNotNull(hello.sasNonce)))
            val codes = ShortAuthString.code(checkNotNull(r.messageTwoHash), checkNotNull(hello.sasNonce)) to ShortAuthString.code(checkNotNull(i.messageTwoHash), nonce)
            assertEquals(codes.first, codes.second)
            return codes
        }
        val (a, b) = sasRun("iPad")
        assertTrue(a in 0..999_999 && b in 0..999_999)
        assertEquals(CryptoErrorCode.invalidLength, codeOf { ShortAuthString.code(ByteArray(31), ByteArray(16)) })
    }

    @Test
    fun streamRejectsTamperingAndWrongKind() {
        val key = ByteArray(32) { 3 }
        val sealed = StreamSender(key).seal(2, byteArrayOf(1, 2, 3))
        assertEquals(CryptoErrorCode.authenticationFailed, codeOf { StreamReceiver(key).open(3, sealed) })
        assertEquals(CryptoErrorCode.messageTooShort, codeOf { StreamReceiver(key).open(2, ByteArray(15)) })
        assertEquals(CryptoErrorCode.messageTooLarge, codeOf { StreamSender(key).seal(2, ByteArray(1_048_560)) })
    }

    @Test
    fun replayWindowEdges() {
        val key = ByteArray(32) { 9 }
        val sender = DatagramSender(key)
        val header = ByteArray(16)
        val packets = List(1100) { sender.seal(header, byteArrayOf(it.toByte())) }
        val receiver = DatagramReceiver(key)
        receiver.open(packets[1099])
        assertEquals(CryptoErrorCode.replayed, codeOf { receiver.open(packets[1099]) })
        assertEquals(CryptoErrorCode.outsideReplayWindow, codeOf { receiver.open(packets[0]) })
        receiver.open(packets[1099 - 1023])
        receiver.open(packets[500])
        assertEquals(CryptoErrorCode.replayed, codeOf { receiver.open(packets[500]) })
        val tampered = packets[600].copyOf().also { it[20] = (it[20].toInt() xor 1).toByte() }
        assertEquals(CryptoErrorCode.authenticationFailed, codeOf { receiver.open(tampered) })
        receiver.open(packets[600]) // gói giả không đốt counter
        assertEquals(CryptoErrorCode.datagramTooShort, codeOf { receiver.open(ByteArray(39)) })
    }

    @Test
    fun resyncRecoversFromFiveEpochJump() {
        val key = ByteArray(32) { 4 }
        val sender = DatagramSender(key)
        repeat(5) { sender.rekey() }
        val packet = sender.seal(ByteArray(16), byteArrayOf(1))
        val receiver = DatagramReceiver(key)
        assertEquals(CryptoErrorCode.unknownEpoch, codeOf { receiver.open(packet) })
        receiver.resync(sender.epoch)
        assertEquals(5L, receiver.epoch)
        assertContentEquals(byteArrayOf(1), receiver.open(packet).payload)
        assertEquals(CryptoErrorCode.unknownEpoch, codeOf { DatagramReceiver(key).resync(65) })
    }

    @Test
    fun senderNeedsRekeyByTime() {
        var now = 0L
        val sender = DatagramSender(ByteArray(32), clock = { now })
        assertTrue(!sender.needsRekey)
        now = DatagramFormat.REKEY_INTERVAL_MS
        assertTrue(sender.needsRekey)
        sender.rekey()
        assertTrue(!sender.needsRekey)
        assertEquals(CryptoErrorCode.invalidLength, codeOf { sender.seal(ByteArray(15), ByteArray(0)) })
    }

    @Test
    fun inMemoryIdentityStoreIsStableUntilDeleted() {
        val store = InMemoryIdentityStore()
        val first = store.loadOrCreate()
        assertContentEquals(first.publicKey, store.loadOrCreate().publicKey)
        store.delete()
        assertTrue(!first.publicKey.contentEquals(store.loadOrCreate().publicKey))
    }
}
