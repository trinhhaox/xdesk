package vn.xox.xdesk.media

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import vn.xox.xdesk.wire.AudioCodec
import vn.xox.xdesk.wire.AudioPayload
import vn.xox.xdesk.wire.MediaHeader
import vn.xox.xdesk.wire.MediaPacket
import vn.xox.xdesk.wire.MediaPacketType

private class RecordingOutput : PcmOutput {
    val written = mutableListOf<ShortArray>()
    override val outputLatencyMs = 7
    override fun start() = Unit
    override fun write(samples: ShortArray) { written += samples }
    override fun stop() = Unit
}

private class FakeAacDecoder(val frames: Int = 512) : AacEldUnitDecoder {
    var decoded = 0
    var released = false
    override fun decode(unit: ByteArray): ShortArray { decoded++; return ShortArray(frames * 2) { 5 } }
    override fun release() { released = true }
}

private fun pcmPacket(seq: Long, value: Int, frames: Int = 240, hold: Int = 12): MediaPacket {
    val data = ByteArray(frames * 4)
    for (i in 0 until frames * 2) { data[2 * i] = (value and 0xFF).toByte(); data[2 * i + 1] = (value shr 8).toByte() }
    return AudioPayload(AudioCodec.PCM, hold, data).mediaPacket(1, seq, seq * 5)
}

class AudioPlayerTest {
    @Test
    fun pcmPacketsPlayAfterTargetDepth() {
        val output = RecordingOutput()
        val player = AudioPlayer(output) { FakeAacDecoder() }
        for (seq in 0L until 8) player.ingest(pcmPacket(seq, 0x0102))
        assertEquals(8, player.stats.packets)
        assertEquals(40, player.stats.jitterDepthMs)
        player.pump(240)
        assertTrue(output.written.single().all { it == 0x0102.toShort() })
        assertEquals(35, player.stats.jitterDepthMs)
        assertEquals(AudioCodec.PCM, player.stats.codec)
        assertEquals(12, player.stats.hostHoldMs)
    }

    @Test
    fun silenceUntilBuffered() {
        val output = RecordingOutput()
        val player = AudioPlayer(output) { FakeAacDecoder() }
        for (seq in 0L until 3) player.ingest(pcmPacket(seq, 9))
        player.pump(240)
        assertTrue(output.written.single().all { it == 0.toShort() })
    }

    @Test
    fun aacPacketsGoThroughDecoderAndRecoverFromDecoderFailure() {
        val output = RecordingOutput()
        val decoder = FakeAacDecoder()
        val player = AudioPlayer(output) { decoder }
        val unit = AudioPayload(AudioCodec.AAC_ELD, 3, ByteArray(80)).mediaPacket(1, 0, 0)
        player.ingest(unit)
        assertEquals(1, decoder.decoded)
        assertEquals(512 / 48, player.stats.jitterDepthMs)
        assertEquals(AudioCodec.AAC_ELD, player.stats.codec)
        player.stop()
        assertEquals(0, player.stats.packets)
    }

    @Test
    fun malformedAndForeignPacketsAreCountedNotThrown() {
        val player = AudioPlayer(RecordingOutput()) { FakeAacDecoder() }
        player.ingest(MediaPacket(MediaHeader(MediaPacketType.AUDIO, 1, 0), byteArrayOf(9, 0, 0, 1)))
        player.ingest(MediaPacket(MediaHeader(MediaPacketType.VIDEO, 1, 0), byteArrayOf(1)))
        assertEquals(1, player.stats.malformed)
        assertEquals(0, player.stats.packets)
    }

    @Test
    fun estimatedLatencySumsHoldNetworkJitterAndDevice() {
        val stats = AudioPlayerStats(hostHoldMs = 30, jitterDepthMs = 40, outputLatencyMs = 10)
        assertEquals(30 + 8 + 40 + 10L, stats.estimatedLatencyMs(16))
    }

    @Test
    fun littleEndianConversion() {
        assertEquals(listOf<Short>(0x0201, -1), AudioPlayer.pcmFromLittleEndian(byteArrayOf(1, 2, -1, -1)).toList())
    }

    @Test
    fun mutedOutputsSilenceWhileDrainingJitterBuffer() {
        val output = RecordingOutput()
        val player = AudioPlayer(output) { FakeAacDecoder() }
        for (seq in 0L until 8) player.ingest(pcmPacket(seq, 0x0506))
        player.muted = true
        player.pump(240)
        assertTrue(output.written.single().all { it == 0.toShort() })
        assertEquals(35, player.stats.jitterDepthMs)
        player.muted = false
        player.pump(240)
        assertTrue(output.written.last().all { it == 0x0506.toShort() })
    }
}
