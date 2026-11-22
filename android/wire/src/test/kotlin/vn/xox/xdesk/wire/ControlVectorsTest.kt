package vn.xox.xdesk.wire

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import vn.xox.xdesk.testing.Vectors
import vn.xox.xdesk.testing.hex
import vn.xox.xdesk.testing.int
import vn.xox.xdesk.testing.list
import vn.xox.xdesk.testing.long
import vn.xox.xdesk.testing.str
import vn.xox.xdesk.wire.json.JsonParser

class ControlVectorsTest {
    private val v = Vectors.load("control-frames.json")

    private fun errorOf(block: () -> Unit): String =
        assertFailsWith<WireException> { block() }.code.name

    @Test
    fun framesRoundTrip() {
        for (f in v.list("frames")) {
            val frame = ControlFrame(checkNotNull(ControlFrameKind.of(f.int("kind"))), f.hex("payloadHex"))
            assertContentEquals(f.hex("hex"), ControlFrameCodec.encode(frame), f.str("name"))
            val decoded = assertNotNull(ControlFrameCodec.decode(f.hex("hex")))
            assertEquals(frame, decoded.frame)
            assertEquals(f.hex("hex").size, decoded.consumed)
        }
    }

    @Test
    fun incompleteFramesNeedMoreData() {
        for (f in v.list("incompleteFrames")) assertNull(ControlFrameCodec.decode(f.hex("hex")), f.str("name"))
    }

    @Test
    fun invalidFramesReportExpectedCode() {
        for (f in v.list("invalidFrames")) {
            assertEquals(f.str("error"), errorOf { ControlFrameCodec.decode(f.hex("hex")) }, f.str("name"))
        }
    }

    @Test
    fun messagesMatchByteForByte() {
        for (m in v.list("messages")) {
            val name = m.str("name")
            val envelope = ControlMessageCodec.decode(m.str("json").toByteArray())
            assertEquals(m.long("id"), envelope.id, name)
            assertEquals(m.str("type"), ControlMessageCodec.typeName(envelope.message), name)
            val frame = ControlFrame(ControlFrameKind.CONTROL, ControlMessageCodec.encode(envelope))
            assertContentEquals(m.hex("frameHex"), ControlFrameCodec.encode(frame), name)
            assertEquals(m.str("json"), String(frame.payload), name)
        }
    }

    @Test
    fun invalidMessagesReportExpectedCode() {
        for (m in v.list("invalidMessages")) {
            assertEquals(m.str("error"), errorOf { ControlMessageCodec.decode(m.str("json").toByteArray()) }, m.str("name"))
        }
    }

    @Test
    fun newMessagesRoundTrip() {
        val cases = listOf(
            ControlMessage.DisplayConfig(1280, 720, 1.5, 60, VideoCodec.HEVC, ScreenMode.MIRROR),
            ControlMessage.DisplayConfig(720, 1560, 2.0, 60, VideoCodec.H264, ScreenMode.MIRROR, MirrorFit.TOUCH),
            ControlMessage.DisplayConfig(2560, 1440, 2.0, 60, VideoCodec.H264, ScreenMode.MIRROR, MirrorFit.NATIVE),
            ControlMessage.DisplayConfig(1080, 1920, 3.0, 60, VideoCodec.HEVC, ScreenMode.EXTEND, videoPaused = true, displayId = 7L),
            ControlMessage.DisplayReconfigure(ControlMessage.DisplayConfig(1080, 1920, 3.0, 60, VideoCodec.HEVC, ScreenMode.MIRROR, MirrorFit.TOUCH)),
            ControlMessage.VideoPause(1),
            ControlMessage.VideoResume(1),
            ControlMessage.ClipOffer(ClipKind.TEXT, 12, "a".repeat(64)),
            ControlMessage.ClipData(ClipKind.IMAGE, 64, "0123456789abcdef".repeat(4)),
            ControlMessage.SystemUnlockResult(true, "unlocked"),
            ControlMessage.MediaKey(MediaKeyKind.VOLUME_UP),
            ControlMessage.DisplayList(listOf(DisplayInfo(1L, "Built-in Retina", 2560L, 1600L, true))),
            ControlMessage.FileStart("f1", "archive.zip", 1_048_576L),
            ControlMessage.FileChunk("f1", 65_536L),
            ControlMessage.FileDone("f1", "b".repeat(64)),
            ControlMessage.FileCancel("f1", "user cancelled"),
            ControlMessage.Reject(ControlMessage.Reject.REASON_REVOKED),
            ControlMessage.PairResult(true),
            ControlMessage.Rekey,
            ControlMessage.RekeyResync(7, ask = true),
            ControlMessage.AgentApprove("r1", "Claude", "Mở TextEdit", 1_700_000_060_000),
            ControlMessage.AgentApprove.response("r1", allow = false),
        )
        for (m in cases) {
            val bytes = ControlMessageCodec.encode(ControlEnvelope(0, m))
            assertEquals(m, ControlMessageCodec.decode(bytes).message)
        }
        assertEquals("""{"id":0,"t":"rekey"}""", String(ControlMessageCodec.encode(ControlEnvelope(0, ControlMessage.Rekey))))
        val mirror = ControlMessageCodec.decode(
            """{"id":1,"t":"display.config","w":10,"h":10,"scale":2.0,"fps":30,"codec":"h264","mode":"mirror"}""".toByteArray(),
        ).message as ControlMessage.DisplayConfig
        assertEquals(ScreenMode.MIRROR, mirror.screenMode)
        assertEquals(ScreenMode.EXTEND, ControlMessage.DisplayConfig(10, 10, 1.0, 30, VideoCodec.H264).screenMode)
        assertEquals(MirrorFit.FIT_DEVICE, mirror.fit)
        assertEquals(null, mirror.mirrorFit)
    }

    @Test
    fun inputTextLimitIsEnforced() {
        val big = ControlMessage.InputText("a".repeat(4097))
        assertEquals("invalidField", errorOf { ControlMessageCodec.encode(ControlEnvelope(1, big)) })
    }

    @Test
    fun clipOfferAndDataValidateSizeAndHash() {
        val zeroOffer = ControlMessage.ClipOffer(ClipKind.TEXT, 0, "a".repeat(64))
        assertEquals("invalidField", errorOf { ControlMessageCodec.encode(ControlEnvelope(1, zeroOffer)) })
        val oversizedData = ControlMessage.ClipData(ClipKind.IMAGE, ClipLimits.MAX_BYTES.toLong() + 1, "a".repeat(64))
        assertEquals("invalidField", errorOf { ControlMessageCodec.encode(ControlEnvelope(1, oversizedData)) })
        val badHash = ControlMessage.ClipData(ClipKind.TEXT, 10, "not-sha256")
        assertEquals("invalidField", errorOf { ControlMessageCodec.encode(ControlEnvelope(1, badHash)) })
    }

    @Test
    fun agentApproveDistinguishesRequestFromResponseAndEnforcesLimits() {
        val request = ControlMessage.AgentApprove("r1", "Claude", "Mở TextEdit", 5)
        assertTrue(request.isRequest)
        assertTrue(!ControlMessage.AgentApprove.response("r1", true).isRequest)
        val bytes = ControlMessageCodec.encode(ControlEnvelope(3, ControlMessage.AgentApprove.response("r", false)))
        assertEquals("""{"allow":false,"id":3,"requestId":"r","t":"agent.approve"}""", String(bytes))
        val long = ControlMessage.AgentApprove("r", "a", "x".repeat(513), 1)
        assertEquals("invalidField", errorOf { ControlMessageCodec.encode(ControlEnvelope(1, long)) })
        assertEquals("invalidField", errorOf { ControlMessageCodec.encode(ControlEnvelope(1, ControlMessage.AgentApprove(""))) })
        assertEquals("malformedJSON", errorOf { ControlMessageCodec.decode("""{"id":1,"t":"agent.approve"}""".toByteArray()) })
    }

    @Test
    fun streamDecoderHandlesSplitAndCoalescedBytes() {
        val frames = v.list("frames").map { it.hex("hex") }
        val all = frames.reduce { a, b -> a + b }
        val decoder = ControlFrameDecoder()
        var count = 0
        for (b in all) {
            decoder.append(byteArrayOf(b))
            while (decoder.next() != null) count++
        }
        assertEquals(frames.size, count)
        assertEquals(0, decoder.bufferedCount)
    }

    @Test
    fun deepJsonIsRejectedNotOverflowed() {
        val deep = "[".repeat(100_000).toByteArray()
        assertFailsWith<vn.xox.xdesk.wire.json.JsonSyntaxException> { JsonParser.parse(deep) }
        assertEquals("malformedJSON", errorOf { ControlMessageCodec.decode(deep) })
    }
}
