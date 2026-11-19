package vn.xox.xdesk.media

import java.io.BufferedOutputStream
import java.io.Closeable
import java.io.DataOutputStream
import java.io.File
import java.io.IOException
import vn.xox.xdesk.wire.AssembledFrame

/**
 * Chỉ để chẩn đoán (bật ở bản debug): ghi nguyên các access unit Annex B mà viewer đưa vào MediaCodec, để phát lại trong
 * DecoderBenchActivity. Tệp chính: mỗi frame `len u32 BE, key u8, pts-ms u32 BE, payload`. Tệp kèm `<tên>.arr`: mỗi frame
 * một `u32 BE` = ms từ lúc frame đầu vào decoder (giờ tới thật, gồm cả giật mạng). Mọi lỗi ghi đều dừng ghi, không ảnh hưởng stream.
 */
class FrameRecorder(file: File) : Closeable {
    private val frames = DataOutputStream(BufferedOutputStream(file.outputStream()))
    private val arrivals = DataOutputStream(BufferedOutputStream(File(file.path + ARRIVAL_SUFFIX).outputStream()))
    private var firstNs = -1L
    private var failed = false

    fun record(frame: AssembledFrame, nowNs: Long) {
        if (failed) return
        if (firstNs < 0) firstNs = nowNs
        try {
            frames.writeInt(frame.data.size)
            frames.writeByte(if (frame.isKeyframe) 1 else 0)
            frames.writeInt(frame.ptsMs.toInt())
            frames.write(frame.data)
            arrivals.writeInt(((nowNs - firstNs) / 1_000_000).toInt())
        } catch (e: IOException) {
            failed = true
        }
    }

    override fun close() {
        try { frames.close(); arrivals.close() } catch (e: IOException) { /* chẩn đoán, bỏ qua */ }
    }

    companion object {
        const val ARRIVAL_SUFFIX = ".arr"
    }
}
