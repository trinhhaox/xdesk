package vn.xox.xdesk.media

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.HandlerThread
import android.os.Process
import android.util.Log
import android.view.Surface
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit
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
    private val onVideoSize: (Int, Int) -> Unit = { _, _ -> },
) {
    private val thread = HandlerThread("xdesk-decode", Process.THREAD_PRIORITY_URGENT_DISPLAY).also { it.start() }
    private val handler = Handler(thread.looper)
    private val pendingCount = AtomicInteger()
    private val pending = ArrayDeque<AssembledFrame>()
    private val freeInputs = ArrayDeque<Int>()
    private val meter = FrameLagMeter(lagWindow)
    private var codec: MediaCodec? = null
    private var activeKey: DecoderKey? = null
    private var waitingForKeyframe = true

    /** Chỉ chẩn đoán: ghi lại mọi access unit đưa vào codec. Gán trước [start]; decoder đóng nó khi [stop]. */
    @Volatile var recorder: FrameRecorder? = null

    /** Số frame đã đưa vào codec nhưng chưa xuất; ≤ 1 nghĩa là decoder không giữ frame. */
    val framesHeld: Int get() = meter.held

    /** Tên codec đang dùng (null khi chưa start). Ghi từ thread decode, đọc từ UI để hiển thị. */
    @Volatile var codecName: String? = null
        private set

    /**
     * Chọn decoder, cấu hình và start. Chạy trên thread decode, tuần tự với [stop]: codec cũ luôn được huỷ xong trước khi dựng codec mới
     * (Surface chỉ nối được một codec), yêu cầu trùng cấu hình đang chạy thì bỏ qua, Surface đã chết thì không configure.
     * Trả `false` (và gọi [onError]) nếu máy không có decoder phù hợp hoặc cấu hình lỗi; `true` kể cả khi bỏ qua vì đã chạy đúng cấu hình.
     */
    fun start(surface: Surface, width: Int, height: Int, extraFormat: Map<String, Int> = emptyMap(), forceCodec: String? = null, mime: String = AndroidCodecList.MIME_AVC): Boolean {
        val task = FutureTask { startOnThread(surface, width, height, extraFormat, forceCodec, mime) }
        if (!handler.post(task)) return false
        return try { task.get(START_TIMEOUT_S, TimeUnit.SECONDS) } catch (e: Exception) { fail("Khởi động decoder thất bại: ${DecoderLifecycle.describe(e)}") }
    }

    private fun startOnThread(surface: Surface, width: Int, height: Int, extraFormat: Map<String, Int>, forceCodec: String?, mime: String): Boolean {
        val key = DecoderKey(surface, width, height, extraFormat, mime)
        when (DecoderLifecycle.plan(activeKey, key, surface.isValid)) {
            StartPlan.SKIP_NO_SURFACE -> { log("bỏ qua start: Surface đã chết"); return false }
            StartPlan.SKIP_UNCHANGED -> return true
            StartPlan.RESTART -> teardown()
            StartPlan.START -> Unit
        }
        val candidates = AndroidCodecList.decoders(mime)
        val choice = (forceCodec?.let { name -> candidates.firstOrNull { it.name == name } } ?: CodecSelector.select(candidates)) ?: return fail("Máy không có decoder cho $mime")
        val quirk = DecoderQuirks.forCodec(choice.name)
        val format = DecoderFormat.build(width, height, quirk, extraFormat, mime)
        var created: MediaCodec? = null
        return try {
            created = MediaCodec.createByCodecName(choice.name)
            created.setCallback(callback, handler)
            created.configure(format, surface, null, 0)
            created.start()
            codec = created
            activeKey = key
            CodecDiagnostics.listDecoders(log)
            CodecDiagnostics.vendorParameters(created, log)
            codecName = choice.name
            waitingForKeyframe = true
            log("decoder=${choice.name} hw=${choice.isHardwareAccelerated} lowLatency=${choice.supportsLowLatency} holdsFrames=${quirk?.mayHoldFrames == true}")
            true
        } catch (e: MediaCodec.CodecException) {
            releaseQuietly(created)
            fail("Không khởi động được decoder ${choice.name}: ${DecoderLifecycle.describe(e, codecDetail(e))}")
        } catch (e: IllegalStateException) {
            releaseQuietly(created)
            fail("Decoder ${choice.name} ở trạng thái sai: ${DecoderLifecycle.describe(e)}")
        } catch (e: IllegalArgumentException) {
            releaseQuietly(created)
            fail("Cấu hình decoder ${choice.name} bị từ chối: ${DecoderLifecycle.describe(e)}")
        }
    }

    private fun codecDetail(e: MediaCodec.CodecException): String = "diagnosticInfo=${e.diagnosticInfo}, errorCode=${e.errorCode}, recoverable=${e.isRecoverable}"

    private fun releaseQuietly(c: MediaCodec?) {
        try { c?.release() } catch (e: RuntimeException) { log("release lỗi: ${DecoderLifecycle.describe(e)}") }
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

    /** Huỷ codec trên thread decode; mọi lỗi của codec đã huỷ bị bỏ qua (xem [callback]). */
    fun stop() {
        handler.post { teardown() }
    }

    private fun teardown() {
        codec?.let {
            try { it.stop() } catch (e: IllegalStateException) { /* đã dừng */ }
            releaseQuietly(it)
        }
        codec = null
        activeKey = null
        codecName = null
        pending.clear(); freeInputs.clear(); pendingCount.set(0); meter.reset()
        recorder?.close(); recorder = null
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
            val nowNs = System.nanoTime()
            meter.onInput(ptsUs, nowNs)
            recorder?.record(frame, nowNs)
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
                log("lag codec=${codecName} samples=${it.samples} p50=${"%.1f".format(it.p50Ms)}ms p95=${"%.1f".format(it.p95Ms)}ms max=${"%.1f".format(it.maxMs)}ms inflight=${"%.1f".format(it.avgInFlight)}/${it.maxInFlight} stuck=${it.stuckEvents}x avg=${"%.1f".format(it.avgStuckFrames)} max=${it.maxStuckFrames} lag=${"%.0f".format(it.maxStuckLagMs)}ms skipped=${it.skipped}(stuck ${it.skippedWhileStuck}) unknown=${it.unknownOutputs}")
            }
        }

        override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
            if (codec !== this@VideoDecoder.codec) return // codec đã bị huỷ (ngắt kết nối/đổi cấu hình): lỗi muộn không đáng báo
            this@VideoDecoder.onError("Decoder lỗi: ${DecoderLifecycle.describe(e, codecDetail(e))}")
        }

        override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
            val width = DecoderFormat.visibleSize(format, MediaFormat.KEY_WIDTH, "crop-left", "crop-right")
            val height = DecoderFormat.visibleSize(format, MediaFormat.KEY_HEIGHT, "crop-top", "crop-bottom")
            if (width > 0 && height > 0) onVideoSize(width, height)
        }
    }

    companion object {
        private const val TAG = "XdeskDecoder"
        const val MAX_PENDING = 8
        private const val START_TIMEOUT_S = 5L
    }
}
