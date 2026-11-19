package vn.xox.xdesk.crypto

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import vn.xox.xdesk.testing.Vectors
import vn.xox.xdesk.testing.hex
import vn.xox.xdesk.testing.int
import vn.xox.xdesk.testing.list
import vn.xox.xdesk.testing.long
import vn.xox.xdesk.testing.obj
import vn.xox.xdesk.testing.str
import vn.xox.xdesk.testing.strings
import vn.xox.xdesk.wire.Hex

/** `crypto-session.json` do Swift sinh ra: Kotlin phải khớp từng byte. */
class SessionVectorsTest {
    private val v = Vectors.load("crypto-session.json")

    @Test
    fun sessionKeysForBothRoles() {
        val s = v.obj("sessionKeys")
        val i = SessionKeys.derive(s.hex("initiatorToResponder"), s.hex("responderToInitiator"), s.hex("handshakeHash"), NoiseRole.INITIATOR)
        val expected = s.obj("initiator")
        assertContentEquals(expected.hex("tcpSend"), i.tcpSend)
        assertContentEquals(expected.hex("tcpReceive"), i.tcpReceive)
        assertContentEquals(expected.hex("udpSend"), i.udpSend)
        assertContentEquals(expected.hex("udpReceive"), i.udpReceive)
        val r = SessionKeys.derive(s.hex("initiatorToResponder"), s.hex("responderToInitiator"), s.hex("handshakeHash"), NoiseRole.RESPONDER)
        assertContentEquals(i.tcpSend, r.tcpReceive)
        assertContentEquals(i.udpSend, r.udpReceive)
        assertEquals("SessionKeys(redacted)", i.toString())
    }

    @Test
    fun datagramsMatchAndReceiveScriptBehaves() {
        val d = v.obj("datagram")
        val header = d.hex("headerHex")
        val packets = d.list("packets")
        val sender = DatagramSender(d.hex("key"))
        for (p in packets) {
            repeat(p.int("rekeysBefore")) { sender.rekey() }
            assertEquals(p.long("epoch"), sender.epoch, p.str("name"))
            assertContentEquals(p.hex("datagramHex"), sender.seal(header, p.hex("payloadHex")), p.str("name"))
        }
        val receiver = DatagramReceiver(d.hex("key"))
        for (step in d.list("receiveScript")) {
            val datagram = packets[step.int("packet")].hex("datagramHex")
            if (step.str("result") == "ok") {
                val opened = receiver.open(datagram)
                assertContentEquals(step.hex("payloadHex"), opened.payload, step.str("name"))
                assertContentEquals(header, opened.header)
            } else {
                val code = assertFailsWith<CryptoException>(step.str("name")) { receiver.open(datagram) }.code
                assertEquals(step.str("result"), code.name, step.str("name"))
            }
        }
    }

    @Test
    fun streamFramesMatch() {
        val s = v.obj("stream")
        val frames = s.list("frames")
        val sender = StreamSender(s.hex("key"))
        val receiver = StreamReceiver(s.hex("key"))
        frames.forEachIndexed { index, f ->
            if (index == s.int("rekeyAfterFrame")) { sender.rekey(); receiver.rekey() }
            val sealed = sender.seal(f.int("kind"), f.hex("plaintextHex"))
            assertContentEquals(f.hex("ciphertextHex"), sealed, f.str("name"))
            assertContentEquals(f.hex("plaintextHex"), receiver.open(f.int("kind"), sealed), f.str("name"))
        }
    }

    @Test
    fun handshakeEnvelopeFramesAndPayloads() {
        val env = v.obj("handshakeEnvelope")
        for (f in env.list("frames")) {
            val bytes = f.hex("hex")
            assertContentEquals(bytes, HandshakeFrame.decode(bytes).encode(), f.str("name"))
        }
        assertEquals(NoisePattern.XX_PSK3, (HandshakeFrame.decode(Hex.decode("000102")) as HandshakeFrame.Begin).pattern)
        for (p in env.list("payloads")) {
            val nonce = p.str("sasNonceHex").takeIf { it.isNotEmpty() }?.let(Hex::decode)
            val payload = HandshakePayload(checkNotNull(DeviceRole.of(p.int("role"))), p.str("name"), nonce)
            assertContentEquals(p.hex("hex"), payload.encode(), p.str("name"))
            assertEquals(payload, HandshakePayload.decode(p.hex("hex")))
        }
    }

    @Test
    fun pairingUriAndFingerprint() {
        val p = v.obj("pairing")
        val uri = PairingURI(p.hex("hostPublicKey"), p.hex("token"), p.strings("addresses"))
        assertEquals(p.str("uri"), uri.string)
        assertEquals(uri, PairingURI.parse(p.str("uri")))
        assertEquals(p.strings("addresses"), PairingURI.parse(p.str("uri")).addresses)
        assertEquals(p.str("fingerprint"), DeviceFingerprint.make(p.hex("hostPublicKey")))
        assertEquals("6668-7AAD-F862-BD77", DeviceFingerprint.make(ByteArray(32)))
    }

    @Test
    fun shortAuthString() {
        val s = v.obj("sas")
        assertContentEquals(s.hex("commitment"), ShortAuthString.commitment(s.hex("ephemeral"), s.hex("static"), s.hex("nonce")))
        assertTrue(ShortAuthString.verify(s.hex("commitment"), s.hex("ephemeral"), s.hex("static"), s.hex("nonce")))
        assertEquals(s.long("code").toInt(), ShortAuthString.code(s.hex("messageTwoHash"), s.hex("nonce")))
        assertEquals(s.str("display"), ShortAuthString.format(s.int("code")))
        for (c in s.list("formatCases")) assertEquals(c.str("display"), ShortAuthString.format(c.int("code")))
    }
}
