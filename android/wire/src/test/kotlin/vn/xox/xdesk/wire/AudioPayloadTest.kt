package vn.xox.xdesk.wire

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import vn.xox.xdesk.testing.Vectors
import vn.xox.xdesk.testing.hex
import vn.xox.xdesk.testing.int
import vn.xox.xdesk.testing.list
import vn.xox.xdesk.testing.long
import vn.xox.xdesk.testing.str

class AudioPayloadTest {
    private val vectors = Vectors.load("audio-payloads.json")

    @Test
    fun sharedVectorsMatchSwiftEncoder() {
        for (c in vectors.list("payloads")) {
            val codec = checkNotNull(AudioCodec.of(c.int("codec")))
            val payload = AudioPayload(codec, c.int("holdMs"), c.hex("dataHex"))
            assertContentEquals(c.hex("hex"), payload.encode(), c.str("name"))
            assertEquals(payload, AudioPayload.decode(c.hex("hex")), c.str("name"))
            val packet = payload.mediaPacket(c.int("streamId"), c.long("sequence"), c.long("ptsMs"))
            assertContentEquals(c.hex("packetHex"), packet.encode(), c.str("name"))
            val back = MediaPacket.decode(c.hex("packetHex"))
            assertEquals(MediaPacketType.AUDIO, back.header.type)
            assertEquals(payload, AudioPayload.decode(back.payload))
        }
    }

    @Test
    fun invalidPayloadsReportExpectedCode() {
        for (c in vectors.list("invalidPayloads")) {
            val code = assertFailsWith<WireException>(c.str("name")) { AudioPayload.decode(c.hex("hex")) }.code.name
            assertEquals(c.str("error"), code, c.str("name"))
        }
    }

    @Test
    fun frameCountFollowsCodec() {
        assertEquals(240, AudioPayload(AudioCodec.PCM, 0, ByteArray(960)).frameCount)
        assertEquals(512, AudioPayload(AudioCodec.AAC_ELD, 0, ByteArray(80)).frameCount)
    }

    @Test
    fun codecCapabilitiesMatchSpecBits() {
        assertEquals(1L shl 2, AudioCodec.PCM.capability)
        assertEquals(1L shl 3, AudioCodec.AAC_ELD.capability)
        assertContentEquals(byteArrayOf(0xF8.toByte(), 0xE6.toByte(), 0x40, 0x00), AudioPayload.AAC_ELD_CONFIG)
    }
}
