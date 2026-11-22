package vn.xox.xdesk.media

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

private fun chunk(frames: Int = 240, value: Short = 1) = ShortArray(frames * 2) { value }

class AudioJitterBufferTest {
    @Test
    fun waitsForTargetDepthBeforePlaying() {
        val jitter = AudioJitterBuffer()
        for (seq in 0L until 7) jitter.push(seq, chunk())
        assertEquals(35, jitter.depthMs)
        assertTrue(jitter.pull(240).all { it == 0.toShort() })
        jitter.push(7, chunk())
        assertEquals(40, jitter.depthMs)
        assertTrue(jitter.pull(240).all { it == 1.toShort() })
        assertEquals(35, jitter.depthMs)
    }

    @Test
    fun underrunPlaysSilenceThenRebuffers() {
        val jitter = AudioJitterBuffer()
        for (seq in 0L until 8) jitter.push(seq, chunk())
        jitter.pull(1920)
        assertTrue(jitter.pull(480).all { it == 0.toShort() })
        assertEquals(1, jitter.counters.underruns)
        jitter.push(8, chunk())
        assertTrue(jitter.pull(240).all { it == 0.toShort() })
    }

    @Test
    fun lateDuplicateAndGapHandling() {
        val jitter = AudioJitterBuffer()
        jitter.push(5, chunk(value = 9))
        jitter.push(5, chunk(value = 9))
        jitter.push(3, chunk(value = 9))
        assertEquals(2, jitter.counters.lateOrDuplicate)
        jitter.push(8, chunk(value = 9))
        assertEquals(480, jitter.counters.concealedFrames)
        assertEquals(240 * 4, jitter.bufferedFrames)
    }

    @Test
    fun hugeGapResetsAndOverflowTrims() {
        val jitter = AudioJitterBuffer()
        jitter.push(0, chunk())
        jitter.push(500, chunk())
        assertEquals(1, jitter.counters.resets)
        assertEquals(240, jitter.bufferedFrames)
        val flooded = AudioJitterBuffer()
        for (seq in 0L until 25) flooded.push(seq, chunk())
        assertTrue(flooded.counters.overflowTrims >= 1)
        assertTrue(flooded.depthMs <= AudioJitterBuffer.OVERFLOW_MS)
    }

    @Test
    fun sequenceWrapAroundIsNotLate() {
        val jitter = AudioJitterBuffer()
        jitter.push(0xFFFFFFFFL, chunk())
        jitter.push(0, chunk())
        assertEquals(0, jitter.counters.lateOrDuplicate)
        assertEquals(0, jitter.counters.concealedFrames)
    }

    @Test
    fun ringBufferWrapsCorrectlyOverManyPulls() {
        val jitter = AudioJitterBuffer()
        var expected = 0
        var seq = 0L
        repeat(2000) {
            jitter.push(seq, ShortArray(480) { (seq % 100).toShort() })
            seq++
            if (jitter.depthMs >= 40) {
                val out = jitter.pull(240)
                expected += out.size
            }
        }
        assertTrue(expected > 0)
        assertEquals(0, jitter.counters.underruns)
    }

    @Test
    fun underrunsDeepenTheBufferUpToTheCap() {
        val buffer = AudioJitterBuffer()
        assertEquals(AudioJitterBuffer.TARGET_MS, buffer.targetMs)
        buffer.push(0, ShortArray(48 * 2 * AudioJitterBuffer.TARGET_MS))
        buffer.pull(48 * (AudioJitterBuffer.TARGET_MS + 10))
        assertEquals(AudioJitterBuffer.TARGET_MS + AudioJitterBuffer.TARGET_STEP_MS, buffer.targetMs)
        repeat(50) { buffer.pull(480) }
        assertTrue(buffer.targetMs <= AudioJitterBuffer.MAX_TARGET_MS)
    }
}
