package vn.xox.xdesk.wire

import java.util.Random
import kotlin.test.Test

/** 10 000 đầu vào ngẫu nhiên: bộ giải mã chỉ được ném [WireException] và phải kết thúc nhanh. */
class DecoderFuzzTest {
    private val random = Random(20261119)

    private fun randomBytes(): ByteArray = ByteArray(random.nextInt(80)).also(random::nextBytes)

    private fun mutate(seed: ByteArray): ByteArray {
        val copy = seed.copyOf()
        repeat(1 + random.nextInt(3)) { if (copy.isNotEmpty()) copy[random.nextInt(copy.size)] = random.nextInt(256).toByte() }
        return if (random.nextBoolean() && copy.isNotEmpty()) copy.copyOf(random.nextInt(copy.size)) else copy
    }

    private fun check(block: () -> Unit) {
        try { block() } catch (_: WireException) { /* lỗi hợp lệ của module */ }
    }

    @Test(timeout = 60_000)
    fun decodersOnlyThrowWireException() {
        val seeds = listOf(
            ControlFrameCodec.encode(ControlFrame(ControlFrameKind.CONTROL, """{"id":1,"t":"ping","t0":5}""".toByteArray())),
            MediaPacket.nack(1, listOf(NackEntry(1, 2))).encode(),
            InputEvent.encodeBatch(listOf(InputEvent(InputKind.MOVE, seq = 1, x = 0.5f, y = 0.5f))),
        )
        repeat(10_000) { i ->
            val bytes = if (i % 2 == 0) randomBytes() else mutate(seeds[i % seeds.size])
            check { ControlFrameCodec.decode(bytes) }
            check { ControlMessageCodec.decode(bytes) }
            check { MediaPacket.decode(bytes) }
            check { NackPayload.decode(bytes) }
            check { InputEvent.decodeBatch(bytes) }
            check { InputAck.decode(bytes) }
            check { ControlFrameDecoder().apply { append(bytes) }.next() }
            check { Reassembler().ingest(MediaPacket.decode(bytes), 0) }
        }
    }

    @Test(timeout = 60_000)
    fun jsonFuzzFromValidMessages() {
        val base = """{"codec":"h264","fps":60,"h":1440,"id":3,"scale":2,"t":"display.config","w":2560}""".toByteArray()
        repeat(10_000) { check { ControlMessageCodec.decode(mutate(base)) } }
    }
}
