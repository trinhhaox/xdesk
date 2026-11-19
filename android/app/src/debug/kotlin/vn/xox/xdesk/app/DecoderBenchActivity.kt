package vn.xox.xdesk.app

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.view.SurfaceHolder
import android.view.SurfaceView
import java.io.File
import java.nio.ByteBuffer
import kotlin.concurrent.thread
import vn.xox.xdesk.media.FrameRecorder
import vn.xox.xdesk.media.VideoDecoder
import vn.xox.xdesk.wire.AssembledFrame

/**
 * Chỉ bản debug: phát một luồng H.264 ghi sẵn (khung: len u32 BE, key u8, pts u32 BE, Annex B) qua [VideoDecoder] đúng nhịp pts,
 * rồi để im [IDLE_MS] để thấy frame kẹt trong decoder. Dùng đo lag/frame-held không cần mạng:
 * `adb push bench.bin /sdcard/Android/data/vn.xox.xdesk/files/` rồi `am start -n vn.xox.xdesk/.app.DecoderBenchActivity --es file bench.bin [--es vk <khoá> --ei vv <giá trị>]`.
 * Phát lại luồng ghi từ phiên thật (`files/live.bin` + `live.bin.arr`, xem FrameRecorder): `--es file live.bin --es timing arrival|even|pts`
 * (arrival = đúng nhịp tới thật gồm giật mạng; even = rải đều; pts = nhịp chụp trên Mac). Tệp được tìm ở files/ nội bộ rồi tới bộ nhớ ngoài.
 * Kết quả đầy đủ ghi vào `files/bench.out` (logcat có thể tràn): `adb exec-out run-as vn.xox.xdesk cat files/bench.out`.
 */
class DecoderBenchActivity : Activity() {
    private var decoder: VideoDecoder? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val name = intent.getStringExtra("file") ?: "bench.bin"
        val width = intent.getIntExtra("w", 1280)
        val height = intent.getIntExtra("h", 720)
        val extra = intent.getStringExtra("vk")?.let { mapOf(it to intent.getIntExtra("vv", 1)) } ?: emptyMap()
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        val view = SurfaceView(this)
        setContentView(view)
        view.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(h: SurfaceHolder) = run(locate(name), h, width, height, extra, intent.getStringExtra("codec"))
            override fun surfaceChanged(h: SurfaceHolder, f: Int, w: Int, hh: Int) = Unit
            override fun surfaceDestroyed(h: SurfaceHolder) { decoder?.release(); decoder = null }
        })
    }

    private fun run(file: File, holder: SurfaceHolder, width: Int, height: Int, extra: Map<String, Int>, codec: String?) {
        val timing = intent.getStringExtra("timing") ?: "pts"
        val frames = try { retime(parse(file), arrivals(file), timing) } catch (e: java.io.IOException) { Log.e(TAG, "không đọc được ${file.path}: ${e.message}"); return }
        val transcript = StringBuffer() // logcat có thể tràn bộ đệm giữa chừng nên đầy đủ kết quả được ghi vào files/bench.out
        val record = { line: String -> Log.i(TAG, line); transcript.append(line).append('\n'); Unit }
        val dec = VideoDecoder({ Log.i(TAG, "keyframe?") }, { Log.e(TAG, "lỗi: $it") }, record, LAG_WINDOW)
        decoder = dec
        if (!dec.start(holder.surface, width, height, extra, codec)) return
        thread(name = "bench-feed") {
            val t0 = System.nanoTime()
            for (f in frames) {
                val wait = f.ptsMs - (System.nanoTime() - t0) / 1_000_000
                if (wait > 0) Thread.sleep(wait)
                dec.submit(f)
            }
            Thread.sleep(IDLE_MS)
            record("bench-end file=${file.name} timing=$timing frames=${frames.size} heldAfterIdle=${dec.framesHeld}")
            File(filesDir, "bench.out").writeText(transcript.toString())
        }
    }

    private fun locate(name: String): File = File(filesDir, name).takeIf { it.exists() } ?: File(getExternalFilesDir(null), name)

    private fun arrivals(file: File): List<Long> {
        val side = File(file.path + FrameRecorder.ARRIVAL_SUFFIX)
        if (!side.exists()) return emptyList()
        val buf = ByteBuffer.wrap(side.readBytes())
        return List(buf.remaining() / 4) { buf.int.toLong() and 0xFFFFFFFFL }
    }

    /** Đổi nhịp phát: `pts` giữ nhịp chụp; `arrival` dùng giờ tới thật; `even` rải đều cùng tổng thời lượng với `arrival`. Giờ luôn tăng chặt (meter khoá theo pts). */
    private fun retime(frames: List<AssembledFrame>, arrival: List<Long>, timing: String): List<AssembledFrame> {
        if (frames.size < 2) return frames
        if (timing != "pts" && arrival.size != frames.size) throw java.io.IOException("thiếu tệp .arr khớp với ${frames.size} frame")
        var prev = -1L
        return frames.mapIndexed { i, f ->
            val raw = when (timing) {
                "arrival" -> arrival[i]
                "even" -> arrival.last() * i / (frames.size - 1)
                else -> f.ptsMs - frames.first().ptsMs
            }
            prev = maxOf(raw, prev + 1)
            AssembledFrame(f.streamId, f.frameNo, prev, f.isKeyframe, f.data)
        }
    }

    private fun parse(file: File): List<AssembledFrame> {
        val buf = ByteBuffer.wrap(file.readBytes())
        val out = ArrayList<AssembledFrame>()
        while (buf.remaining() > 9) {
            val len = buf.int
            val key = buf.get().toInt() != 0
            val pts = buf.int.toLong() and 0xFFFFFFFFL
            if (len < 0 || len > buf.remaining()) throw java.io.IOException("file hỏng")
            out += AssembledFrame(0, out.size.toLong(), pts, key, ByteArray(len).also { buf.get(it) })
        }
        return out
    }

    private companion object {
        const val TAG = "XdeskBench"
        const val LAG_WINDOW = 30
        const val IDLE_MS = 3000L
    }
}
