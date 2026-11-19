package vn.xox.xdesk.wire

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import vn.xox.xdesk.testing.Vectors
import vn.xox.xdesk.testing.bool
import vn.xox.xdesk.testing.hex
import vn.xox.xdesk.testing.int
import vn.xox.xdesk.testing.list
import vn.xox.xdesk.testing.long
import vn.xox.xdesk.testing.str
import vn.xox.xdesk.testing.strings

class MediaVectorsTest {
    private val media = Vectors.load("media-headers.json")
    private val input = Vectors.load("input-events.json")

    private fun errorOf(block: () -> Unit): String = assertFailsWith<WireException> { block() }.code.name

    @Test
    fun packetsEncodeAndDecode() {
        for (p in media.list("packets")) {
            val header = MediaHeader(
                checkNotNull(MediaPacketType.of(p.int("type"))), p.int("streamId"), p.long("frameNo"), p.int("fragIdx"),
                p.int("fragCnt"), p.bool("keyframe"), p.long("ptsMs"),
            )
            val packet = MediaPacket(header, p.hex("payloadHex"))
            assertContentEquals(p.hex("hex"), packet.encode(), p.str("name"))
            assertEquals(packet, MediaPacket.decode(p.hex("hex")), p.str("name"))
        }
    }

    @Test
    fun invalidPacketsReportExpectedCode() {
        for (p in media.list("invalidPackets")) {
            assertEquals(p.str("error"), errorOf { MediaPacket.decode(p.hex("hex")) }, p.str("name"))
        }
    }

    @Test
    fun probeBuilderMatchesSpecExample() {
        assertContentEquals(
            Hex.decode("0150000300000000000000010000000001234567" + "89abcdef"),
            MediaPacket.probe(3, 0x0123456789abcdefL).encode(),
        )
        assertEquals(16, MediaPacket.probe(3).encode().size)
    }

    @Test
    fun nackPayloads() {
        for (n in media.list("nack")) {
            val entries = n.list("entries").map { NackEntry(it.long("frameNo"), it.int("fragIdx")) }
            assertContentEquals(n.hex("payloadHex"), NackPayload.encode(entries), n.str("name"))
            assertEquals(entries, NackPayload.decode(n.hex("payloadHex")))
        }
        for (n in media.list("invalidNack")) {
            assertEquals(n.str("error"), errorOf { NackPayload.decode(n.hex("payloadHex")) }, n.str("name"))
        }
    }

    @Test
    fun packetizerMatchesVectors() {
        for (p in media.list("packetizer")) {
            val packets = Packetizer(p.int("streamId"), p.int("maxPayload"))
                .packetize(p.hex("frameHex"), p.long("frameNo"), p.long("ptsMs"), p.bool("keyframe"))
            val expected = p.strings("packetsHex")
            assertEquals(expected.size, packets.size, p.str("name"))
            expected.forEachIndexed { i, hex -> assertContentEquals(Hex.decode(hex), packets[i].encode(), p.str("name")) }
        }
    }

    @Test
    fun inputEventsRoundTrip() {
        for (e in input.list("events")) {
            val event = InputEvent(
                checkNotNull(InputKind.of(e.int("kind"))), e.int("button"), e.int("mods"), e.long("seq"),
                floatOf(e, "x"), floatOf(e, "y"), floatOf(e, "dx"), floatOf(e, "dy"), e.int("keyUsage"),
            )
            assertContentEquals(e.hex("hex"), InputEvent.encodeBatch(listOf(event)), e.str("name"))
            assertEquals(listOf(event), InputEvent.decodeBatch(e.hex("hex")), e.str("name"))
        }
        assertEquals(input.int("eventSize"), InputEvent.SIZE)
    }

    @Test
    fun inputBatchesAcksAndInvalid() {
        for (b in input.list("batches")) {
            val events = InputEvent.decodeBatch(b.hex("payloadHex"))
            assertEquals(b.int("count"), events.size)
            assertContentEquals(b.hex("payloadHex"), InputEvent.encodeBatch(events))
        }
        for (a in input.list("acks")) {
            assertContentEquals(a.hex("hex"), InputAck(a.long("seq")).encode())
            assertEquals(a.long("seq"), InputAck.decode(a.hex("hex")).seq)
        }
        for (i in input.list("invalid")) {
            assertEquals(i.str("error"), errorOf { InputEvent.decodeBatch(i.hex("payloadHex")) }, i.str("name"))
        }
    }

    private fun floatOf(obj: vn.xox.xdesk.wire.json.JsonObject, key: String): Float =
        (obj.value(key) as vn.xox.xdesk.wire.json.JsonNumber).double.toFloat()

    private fun vn.xox.xdesk.wire.json.JsonObject.value(key: String) = checkNotNull(this[key])
}
