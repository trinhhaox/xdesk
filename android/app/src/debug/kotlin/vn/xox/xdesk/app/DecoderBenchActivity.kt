package vn.xox.xdesk.app

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.view.SurfaceHolder
import android.view.SurfaceView
import java.io.File
import java.nio.ByteBuffer
import kotlin.concurrent.thread
import vn.xox.xdesk.media.VideoDecoder
import vn.xox.xdesk.wire.AssembledFrame

/**
 * Chỉ bản debug: phát một luồng H.264 ghi sẵn (khung: len u32 BE, key u8, pts u32 BE, Annex B) qua [VideoDecoder] đúng nhịp pts,
 * rồi để im [IDLE_MS] để thấy frame kẹt trong decoder. Dùng đo lag/frame-held không cần mạng:
 * `adb push bench.bin /sdcard/Android/data/vn.xox.xdesk/files/` rồi `am start -n vn.xox.xdesk/.app.DecoderBenchActivity --es file bench.bin [--es vk <khoá> --ei vv <giá trị>]`.
 */
class DecoderBenchActivity : Activity() {
    private var decoder: VideoDecoder? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val name = intent.getStringExtra("file") ?: "bench.bin"
        val width = intent.getIntExtra("w", 1280)
        val height = intent.getIntExtra("h", 720)
        val extra = intent.getStringExtra("vk")?.let { mapOf(it to intent.getIntExtra("vv", 1)) } ?: emptyMap()
        val view = SurfaceView(this)
        setContentView(view)
        view.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(h: SurfaceHolder) = run(File(getExternalFilesDir(null), name), h, width, height, extra, intent.getStringExtra("codec"))
            override fun surfaceChanged(h: SurfaceHolder, f: Int, w: Int, hh: Int) = Unit
            override fun surfaceDestroyed(h: SurfaceHolder) { decoder?.release(); decoder = null }
        })
    }

    private fun run(file: File, holder: SurfaceHolder, width: Int, height: Int, extra: Map<String, Int>, codec: String?) {
        val frames = try { parse(file) } catch (e: java.io.IOException) { Log.e(TAG, "không đọc được ${file.path}: ${e.message}"); return }
        val dec = VideoDecoder({ Log.i(TAG, "keyframe?") }, { Log.e(TAG, "lỗi: $it") }, lagWindow = LAG_WINDOW)
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
            Log.i(TAG, "bench-end file=${file.name} frames=${frames.size} heldAfterIdle=${dec.framesHeld}")
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
