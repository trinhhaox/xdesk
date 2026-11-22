package vn.xox.xdesk.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import vn.xox.xdesk.transport.ClipboardAccess
import vn.xox.xdesk.transport.ClipboardItem
import vn.xox.xdesk.wire.ClipKind
import vn.xox.xdesk.wire.ClipLimits

/** Cầu nối [ClipboardAccess] với `ClipboardManager` của Android (hỗ trợ văn bản UTF-8 và ảnh PNG, chặn mục nhạy cảm). */
class AndroidClipboardAccess(context: Context) : ClipboardAccess {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun manager(): ClipboardManager? =
        appContext.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager

    override fun read(): ClipboardItem? = runOnMain {
        val cm = manager() ?: return@runOnMain null
        val clip = cm.primaryClip ?: return@runOnMain null
        if (clip.itemCount == 0) return@runOnMain null
        val description = clip.description
        if (description.extras?.getBoolean(EXTRA_IS_SENSITIVE, false) == true) return@runOnMain null

        val item = clip.getItemAt(0)
        val uri = item.uri
        if (uri != null) {
            val mime = runCatching { appContext.contentResolver.getType(uri) }.getOrNull()
            if (mime?.startsWith("image/") == true || description.hasMimeType("image/*")) {
                readImageUri(uri)?.let { return@runOnMain it }
            }
        }
        val text = item.text?.toString() ?: item.coerceToText(appContext)?.toString()
        if (!text.isNullOrEmpty()) return@runOnMain ClipboardItem.text(text)
        null
    }

    override fun write(item: ClipboardItem) {
        runOnMain {
            val cm = manager() ?: return@runOnMain
            when (item.kind) {
                ClipKind.TEXT -> {
                    val text = item.text ?: return@runOnMain
                    runCatching { cm.setPrimaryClip(ClipData.newPlainText("Xdesk", text)) }
                }
                ClipKind.IMAGE -> {
                    runCatching {
                        val dir = File(appContext.cacheDir, "clipboard").apply { mkdirs() }
                        val outFile = File(dir, "xdesk-clip.png")
                        outFile.writeBytes(item.data)
                        val uri = FileProvider.getUriForFile(appContext, "${appContext.packageName}.fileprovider", outFile)
                        cm.setPrimaryClip(ClipData.newUri(appContext.contentResolver, "Xdesk", uri))
                    }
                }
            }
        }
    }

    private fun readImageUri(uri: android.net.Uri): ClipboardItem? = runCatching {
        val rawBytes = appContext.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return null
        ClipboardItem.of(ClipKind.IMAGE, rawBytes)?.let { return it }
        val bitmap = BitmapFactory.decodeByteArray(rawBytes, 0, rawBytes.size) ?: return null
        val pngOut = ByteArrayOutputStream()
        try {
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, pngOut)) return null
            val bytes = pngOut.toByteArray()
            if (bytes.size > ClipLimits.MAX_BYTES) return null
            ClipboardItem.of(ClipKind.IMAGE, bytes)
        } finally {
            bitmap.recycle()
        }
    }.getOrNull()

    private fun <T> runOnMain(block: () -> T): T? {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return runCatching(block).getOrNull()
        }
        val result = AtomicReference<T?>()
        val latch = CountDownLatch(1)
        if (!mainHandler.post {
                result.set(runCatching(block).getOrNull())
                latch.countDown()
            }
        ) {
            return null
        }
        latch.await(1000L, TimeUnit.MILLISECONDS)
        return result.get()
    }

    companion object {
        private const val EXTRA_IS_SENSITIVE = "android.content.extra.IS_SENSITIVE"
    }
}
