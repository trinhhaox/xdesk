package vn.xox.xdesk.wire

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ReassemblerTest {
    private val packetizer = Packetizer(streamId = 1, maxPayload = 4)

    private fun frame(n: Int, size: Int = 10) = ByteArray(size) { (n + it).toByte() }

    private fun packets(frameNo: Long, size: Int = 10) = packetizer.packetize(frame(frameNo.toInt(), size), frameNo, 100, true)

    @Test
    fun reassemblesOutOfOrderAndIgnoresDuplicates() {
        val r = Reassembler()
        val p = packets(0)
        assertNull(r.ingest(p[2], 0))
        assertNull(r.ingest(p[0], 0))
        assertNull(r.ingest(p[0], 0))
        val done = assertNotNull(r.ingest(p[1], 0))
        assertContentEquals(frame(0), done.data)
        assertTrue(done.isKeyframe)
        assertNull(r.ingest(p[1], 0))
        assertEquals(1, r.watermark)
    }

    @Test
    fun lossLeavesPendingAndGaps() {
        val r = Reassembler()
        r.ingest(packets(0)[0], 10)
        packets(2).forEach { r.ingest(it, 20) }
        assertEquals(listOf(1L), r.gaps)
        assertEquals(listOf(PendingFrame(0, listOf(1, 2), 10, true)), r.pending)
    }

    @Test
    fun inconsistentFragmentCountIsRejected() {
        val r = Reassembler()
        r.ingest(packets(5, 10)[0], 0)
        val bad = Packetizer(1, 4).packetize(frame(5, 20), 5, 100)[1]
        assertEquals(WireErrorCode.inconsistentFragmentCount, assertFailsWith<WireException> { r.ingest(bad, 0) }.code)
    }

    @Test
    fun nonMediaPacketsAreRejected() {
        val ack = MediaPacket.inputAck(1, InputAck(1))
        assertEquals(WireErrorCode.unexpectedPacketType, assertFailsWith<WireException> { Reassembler().ingest(ack, 0) }.code)
    }

    @Test
    fun windowOverflowAbandonsOldestFrames() {
        val r = Reassembler()
        r.ingest(packets(0)[0], 0)
        packets(300).forEach { r.ingest(it, 0) }
        assertTrue(r.watermark > 0)
        assertTrue(r.pending.none { it.frameNo == 0L })
        assertTrue(r.abandonedCount >= 1)
    }

    @Test(timeout = 5000)
    fun hugeFrameJumpDoesNotHang() {
        val r = Reassembler()
        r.ingest(packets(0)[0], 0)
        for (frameNo in longArrayOf(0xFFFF_FFF0L, 0x8000_0000L, 0xFFFF_FFFEL, 1_000_000_000L)) {
            packets(frameNo).forEach { r.ingest(it, 0) }
        }
        assertTrue(r.gaps.size <= Reassembler.WINDOW)
        NackTracker().poll(r, 1000)
    }

    @Test
    fun nackTrackerRequestsThenGivesUp() {
        val r = Reassembler()
        val tracker = NackTracker()
        r.ingest(packets(0)[0], 0)
        packets(1).forEach { r.ingest(it, 0) }
        assertEquals(0, tracker.poll(r, 10).nacks.size)
        assertEquals(listOf(NackEntry(0, 1), NackEntry(0, 2)), tracker.poll(r, 25).nacks)
        assertEquals(0, tracker.poll(r, 40).nacks.size)
        assertEquals(2, tracker.poll(r, 70).nacks.size)
        assertEquals(listOf(0L), tracker.poll(r, 600).abandoned)
        assertEquals(2, r.watermark)
    }

    @Test
    fun nackTrackerAsksWholeFrameForGap() {
        val r = Reassembler()
        packets(1).forEach { r.ingest(it, 0) }
        val tracker = NackTracker()
        tracker.poll(r, 0)
        assertEquals(listOf(NackEntry(0, NackEntry.WHOLE_FRAME)), tracker.poll(r, 30).nacks)
    }

    @Test
    fun abandonBeforeDropsEverythingBelow() {
        val r = Reassembler()
        r.ingest(packets(1)[0], 0)
        r.abandonBefore(0xFFFF_FFFFL - 10)
        assertEquals(0xFFFF_FFFFL - 10, r.watermark)
        assertTrue(r.pending.isEmpty())
        r.abandonBefore(5)
        assertEquals(0xFFFF_FFFFL - 10, r.watermark)
    }
}
