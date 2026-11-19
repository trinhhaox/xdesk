package vn.xox.xdesk.media

import java.io.DataInputStream
import java.io.File
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import vn.xox.xdesk.wire.AssembledFrame

class FrameRecorderTest {
    @Test
    fun recordsBenchFormatAndArrivalSidecar() {
        val file = File.createTempFile("live", ".bin").also { it.deleteOnExit() }
        File(file.path + FrameRecorder.ARRIVAL_SUFFIX).deleteOnExit()
        val payload = byteArrayOf(0, 0, 0, 1, 0x65, 9)
        FrameRecorder(file).use {
            it.record(AssembledFrame(0, 0, 1000, true, payload), 5_000_000_000)
            it.record(AssembledFrame(0, 1, 1017, false, byteArrayOf(1, 2)), 5_033_000_000)
        }
        DataInputStream(file.inputStream()).use {
            assertEquals(payload.size, it.readInt())
            assertEquals(1, it.readUnsignedByte())
            assertEquals(1000, it.readInt())
            assertContentEquals(payload, it.readNBytes(payload.size))
            assertEquals(2, it.readInt())
            assertEquals(0, it.readUnsignedByte())
            assertEquals(1017, it.readInt())
        }
        DataInputStream(File(file.path + FrameRecorder.ARRIVAL_SUFFIX).inputStream()).use {
            assertEquals(0, it.readInt())
            assertEquals(33, it.readInt())
        }
    }
}
