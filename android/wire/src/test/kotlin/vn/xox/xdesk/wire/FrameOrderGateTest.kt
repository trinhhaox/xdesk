package vn.xox.xdesk.wire

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FrameOrderGateTest {
    private fun frame(n: Long, key: Boolean = false) = AssembledFrame(1, n, n * 16, key, byteArrayOf(n.toByte()))

    private fun FrameOrderGate.Output.nos() = frames.map { it.frameNo }

    @Test
    fun inOrderFramesReleaseImmediatelyWithoutHold() {
        val gate = FrameOrderGate()
        for (n in 0L until 5L) {
            val out = gate.push(frame(n, n == 0L), n)
            assertEquals(listOf(n), out.nos())
            assertNull(out.skipTo)
            assertFalse(out.keyframeNeeded)
        }
        assertFalse(gate.isHolding)
    }

    @Test
    fun idrCompletingAfterPFramesReleasesInOrder() {
        val gate = FrameOrderGate()
        assertTrue(gate.push(frame(1), 0).frames.isEmpty())
        assertTrue(gate.push(frame(2), 5).frames.isEmpty())
        val out = gate.push(frame(0, true), 30)
        assertEquals(listOf(0L, 1L, 2L), out.nos())
        assertFalse(out.keyframeNeeded)
        assertNull(out.skipTo)
        assertFalse(gate.isHolding)
    }

    @Test
    fun missingPFrameTimesOutThenSkipsAndRequestsKeyframe() {
        val gate = FrameOrderGate()
        gate.push(frame(0, true), 0)
        assertTrue(gate.push(frame(2), 10).frames.isEmpty())
        assertTrue(gate.push(frame(3), 12).frames.isEmpty())
        assertTrue(gate.poll(10 + FrameOrderGate.HOLD_BOUND_MS - 1, emptySet()).frames.isEmpty())
        val out = gate.poll(10 + FrameOrderGate.HOLD_BOUND_MS, emptySet())
        assertEquals(listOf(2L, 3L), out.nos())
        assertEquals(2L, out.skipTo)
        assertTrue(out.keyframeNeeded)
        assertTrue(gate.push(frame(1), 80).frames.isEmpty())
        assertEquals(listOf(4L), gate.push(frame(4), 81).nos())
    }

    @Test
    fun missingIdrWaitsForNextKeyframe() {
        val gate = FrameOrderGate()
        gate.push(frame(1), 0)
        gate.push(frame(2), 1)
        val out = gate.poll(100, setOf(0L))
        assertTrue(out.frames.isEmpty())
        assertTrue(out.keyframeNeeded)
        assertEquals(1L, out.skipTo)
        val later = gate.push(frame(3), 110)
        assertTrue(later.frames.isEmpty())
        assertTrue(later.keyframeNeeded)
        val idr = gate.push(frame(10, true), 200)
        assertEquals(listOf(10L), idr.nos())
        assertEquals(10L, idr.skipTo)
        assertEquals(listOf(11L), gate.push(frame(11), 201).nos())
    }

    @Test
    fun completedKeyframeJumpsOverMissingFrames() {
        val gate = FrameOrderGate()
        gate.push(frame(0, true), 0)
        gate.push(frame(2), 1)
        val out = gate.push(frame(5, true), 2)
        assertEquals(listOf(5L), out.nos())
        assertEquals(5L, out.skipTo)
        assertFalse(out.keyframeNeeded)
        assertFalse(gate.isHolding)
    }

    @Test
    fun duplicatesAndStaleFramesAreIgnored() {
        val gate = FrameOrderGate()
        assertEquals(1, gate.push(frame(0, true), 0).frames.size)
        assertTrue(gate.push(frame(0, true), 1).frames.isEmpty())
        gate.push(frame(2), 2)
        assertTrue(gate.push(frame(2), 3).frames.isEmpty())
        assertEquals(listOf(1L, 2L), gate.push(frame(1), 4).nos())
        assertTrue(gate.push(frame(1), 5).frames.isEmpty())
    }

    @Test(timeout = 60_000)
    fun hugeFrameJumpStaysCheap() {
        val gate = FrameOrderGate()
        gate.push(frame(0, true), 0)
        val far = 0xFFFF_FFFFL - 10
        assertTrue(gate.push(frame(far), 1).frames.isEmpty())
        val out = gate.poll(1 + FrameOrderGate.HOLD_BOUND_MS, emptySet())
        assertEquals(listOf(far), out.nos())
        assertEquals(far, out.skipTo)
        assertEquals(listOf(far + 5), gate.push(frame(far + 5, true), 100).nos())
    }
}
