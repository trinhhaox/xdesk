package vn.xox.xdesk.media

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Process
import android.util.Log
import android.view.Surface
import java.util.concurrent.atomic.AtomicInteger
import vn.xox.xdesk.wire.AssembledFrame

/**
 * Giải mã H.264 (Annex B, SPS/PPS nằm trong keyframe) bằng MediaCodec chế độ async, xuất thẳng ra [Surface] của SurfaceView.
 * Mọi thao tác codec chạy trên một thread ưu tiên cao; [submit] gọi được từ thread bất kỳ. Không bao giờ ghi payload vào log.
 * Chưa kiểm chứng trên thiết bị thật (xem phase 07b): các khoá low-latency của hãng là best-effort.
 */
class VideoDecoder(
    private val onNeedKeyframe: () -> Unit,
    private val onError: (String) -> Unit,
    private val log: (String) -> Unit = { Log.i(TAG, it) },
    lagWindow: Int = 120,
) {
    private val thread = HandlerThread("xdesk-decode", Process.THREAD_PRIORITY_URGENT_DISPLAY).also { it.start() }
    private val handler = Handler(thread.looper)
    private val pendingCount = AtomicInteger()
    private val pending = ArrayDeque<AssembledFrame>()
    private val freeInputs = ArrayDeque<Int>()
    private val meter = FrameLagMeter(lagWindow)
    private var codec: MediaCodec? = null
    private var waitingForKeyframe = true

    /** Số frame đã đưa vào codec nhưng chưa xuất; ≤ 1 nghĩa là decoder không giữ frame. */
    val framesHeld: Int get() = meter.held

    /** Tên codec đang dùng (null khi chưa start). Ghi từ thread decode, đọc từ UI để hiển thị. */
    @Volatile var codecName: String? = null
        private set

    /** Chọn decoder, cấu hình và start. Trả `false` (và gọi [onError]) nếu máy không có decoder H.264 hoặc cấu hình lỗi. */
    fun start(surface: Surface, width: Int, height: Int, extraFormat: Map<String, Int> = emptyMap(), forceCodec: String? = null): Boolean {
        val candidates = AndroidCodecList.decoders()
        val choice = (forceCodec?.let { name -> candidates.firstOrNull { it.name == name } } ?: CodecSelector.select(candidates)) ?: return fail("Máy không có decoder H.264")
        val quirk = DecoderQuirks.forCodec(choice.name)
        val format = MediaFormat.createVideoFormat(AndroidCodecList.MIME_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_LOW_LATENCY, 1) // gửi cả khi không quảng bá FEATURE_LowLatency: codec không biết thì bỏ qua
            setInteger(MediaFormat.KEY_PRIORITY, 0)
            setInteger(MediaFormat.KEY_OPERATING_RATE, Short.MAX_VALUE.toInt())
            quirk?.maxInputSizeBytes?.let { setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, it) }
            quirk?.lowLatencyKeys?.forEach { (key, value) -> setInteger(key, value) }
            extraFormat.forEach { (key, value) -> setInteger(key, value) }
        }
        return try {
            val created = MediaCodec.createByCodecName(choice.name)
            created.setCallback(callback, handler)
            created.configure(format, surface, null, 0)
            created.start()
            codec = created
            CodecDiagnostics.listDecoders(log)
            CodecDiagnostics.vendorParameters(created, log)
            codecName = choice.name
            waitingForKeyframe = true
            log("decoder=${choice.name} hw=${choice.isHardwareAccelerated} lowLatency=${choice.supportsLowLatency} holdsFrames=${quirk?.mayHoldFrames == true}")
            true
        } catch (e: MediaCodec.CodecException) {
            fail("Không khởi động được decoder ${choice.name}: ${e.diagnosticInfo}")
        } catch (e: IllegalStateException) {
            fail("Decoder ${choice.name} ở trạng thái sai: ${e.message}")
        } catch (e: IllegalArgumentException) {
            fail("Cấu hình decoder ${choice.name} bị từ chối: ${e.message}")
        }
    }

    /** Đưa một frame đã ghép vào hàng đợi; hàng đợi quá đầy → bỏ hết tới keyframe kế và xin keyframe mới. */
    fun submit(frame: AssembledFrame) {
        if (pendingCount.incrementAndGet() > MAX_PENDING) {
            pendingCount.decrementAndGet()
            handler.post { dropBacklog() }
            return
        }
        handler.post { enqueue(frame) }
    }

    fun stop() {
        handler.post {
            codec?.let {
                try { it.stop() } catch (e: IllegalStateException) { /* đã dừng */ }
                it.release()
            }
            codec = null
            codecName = null
            pending.clear(); freeInputs.clear(); pendingCount.set(0); meter.reset()
        }
    }

    fun release() {
        stop()
        thread.quitSafely()
    }

    private fun enqueue(frame: AssembledFrame) {
        if (codec == null) { pendingCount.decrementAndGet(); return }
        if (waitingForKeyframe && !frame.isKeyframe) {
            pendingCount.decrementAndGet()
            onNeedKeyframe()
            return
        }
        if (frame.isKeyframe) waitingForKeyframe = false
        pending.addLast(frame)
        feed()
    }

    private fun dropBacklog() {
        pendingCount.addAndGet(-pending.size)
        pending.clear()
        waitingForKeyframe = true
        onNeedKeyframe()
    }

    private fun feed() {
        val active = codec ?: return
        while (pending.isNotEmpty() && freeInputs.isNotEmpty()) {
            val index = freeInputs.removeFirst()
            val frame = pending.removeFirst()
            pendingCount.decrementAndGet()
            val buffer = active.getInputBuffer(index)
            if (buffer == null || frame.data.size > buffer.capacity()) {
                active.queueInputBuffer(index, 0, 0, 0, 0)
                waitingForKeyframe = true
                onNeedKeyframe()
                continue
            }
            buffer.clear()
            buffer.put(frame.data)
            val ptsUs = frame.ptsMs * 1000
            meter.onInput(ptsUs, System.nanoTime())
            active.queueInputBuffer(index, 0, frame.data.size, ptsUs, if (frame.isKeyframe) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
        }
    }

    private fun fail(message: String): Boolean {
        onError(message)
        return false
    }

    private val callback = object : MediaCodec.Callback() {
        override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
            freeInputs.addLast(index)
            feed()
        }

        override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
            try { codec.releaseOutputBuffer(index, true) } catch (e: IllegalStateException) { return }
            meter.onOutput(info.presentationTimeUs, System.nanoTime())?.let {
                log("lag codec=${codecName} samples=${it.samples} p50=${"%.1f".format(it.p50Ms)}ms p95=${"%.1f".format(it.p95Ms)}ms max=${"%.1f".format(it.maxMs)}ms held=${"%.1f".format(it.avgFramesHeld)}/${it.maxFramesHeld}")
            }
        }

        override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
            this@VideoDecoder.onError("Decoder lỗi: ${e.diagnosticInfo}")
        }

        override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) = Unit
    }

    companion object {
        private const val TAG = "XdeskDecoder"
        const val MAX_PENDING = 8
    }
}
