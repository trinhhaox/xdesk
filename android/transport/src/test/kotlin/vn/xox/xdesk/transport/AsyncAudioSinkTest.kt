package vn.xox.xdesk.transport

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import vn.xox.xdesk.wire.MediaHeader
import vn.xox.xdesk.wire.MediaPacket
import vn.xox.xdesk.wire.MediaPacketType

class AsyncAudioSinkTest {
    private fun packet(seq: Long) = MediaPacket(MediaHeader(MediaPacketType.AUDIO, 1, seq), byteArrayOf(0, 0, 5))

    @Test
    fun blockedDecoderNeverBlocksTheCaller() {
        val release = CountDownLatch(1)
        val delegate = object : AudioSink {
            override fun start() = Unit
            override fun onPacket(packet: MediaPacket) { release.await() }
            override fun stop() = Unit
        }
        val sink = AsyncAudioSink(delegate, capacity = 4)
        sink.start()
        val started = System.nanoTime()
        repeat(200) { sink.onPacket(packet(it.toLong())) }
        val elapsedMs = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started)
        assertTrue(elapsedMs < 500, "onPacket bị chặn $elapsedMs ms")
        assertTrue(sink.droppedPackets > 0)
        release.countDown()
        sink.stop()
    }

    @Test
    fun packetsReachDelegateInOrder() {
        val received = mutableListOf<Long>()
        val done = CountDownLatch(5)
        val delegate = object : AudioSink {
            override fun start() = Unit
            override fun onPacket(packet: MediaPacket) {
                synchronized(received) { received += packet.header.frameNo }
                done.countDown()
            }
            override fun stop() = Unit
        }
        val sink = AsyncAudioSink(delegate)
        sink.start()
        for (seq in 0L until 5) sink.onPacket(packet(seq))
        assertTrue(done.await(2, TimeUnit.SECONDS))
        sink.stop()
        assertEquals(listOf(0L, 1L, 2L, 3L, 4L), received)
    }
}
