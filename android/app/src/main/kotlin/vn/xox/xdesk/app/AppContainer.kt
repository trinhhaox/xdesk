package vn.xox.xdesk.app

import android.app.Application
import android.util.Log
import android.content.Context
import android.content.pm.ApplicationInfo
import java.io.File
import vn.xox.xdesk.app.identity.IdentityUnavailableException
import vn.xox.xdesk.app.identity.KeystoreIdentityStore
import vn.xox.xdesk.app.update.UpdateController
import vn.xox.xdesk.crypto.DeviceIdentity
import vn.xox.xdesk.crypto.IdentityStore
import vn.xox.xdesk.media.FrameRecorder
import vn.xox.xdesk.transport.FileKnownHostStore
import vn.xox.xdesk.transport.KnownHostStore
import vn.xox.xdesk.transport.ViewerTrust

/** Dựng tay các thành phần dùng chung (không DI framework: app nhỏ). Lưu trong [XdeskApplication]. */
class AppContainer(context: Context) {
    private val appContext = context.applicationContext
    val identityStore: IdentityStore = KeystoreIdentityStore(File(context.filesDir, "identity.v1"))
    val knownHosts: KnownHostStore = FileKnownHostStore(File(context.filesDir, "known-hosts.txt"))

    val updates = UpdateController(context)

    /** `null` kèm [identityError] khi Keystore mất khoá: UI cho người dùng chọn đặt lại danh tính. */
    var identity: DeviceIdentity? = null
        private set
    var identityError: String? = null
        private set

    init { loadIdentity() }

    private fun loadIdentity() {
        try {
            identity = identityStore.loadOrCreate()
            identityError = null
        } catch (e: IdentityUnavailableException) {
            identity = null
            identityError = e.message
        }
    }

    /** Xoá khoá cũ và tạo danh tính mới; mọi host đã ghép phải ghép lại (host biết khoá cũ). */
    fun resetIdentity() {
        identityStore.delete()
        loadIdentity()
    }

    /**
     * Chẩn đoán decoder: chỉ ở bản debuggable và khi tồn tại tệp cờ `files/record-stream`, ghi luồng đang xem vào `files/live.bin`
     * (xem [FrameRecorder]) để phát lại trong DecoderBenchActivity. Bản phát hành luôn trả `null`.
     */
    fun streamRecorder(): FrameRecorder? {
        val debuggable = appContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (!debuggable || !File(appContext.filesDir, RECORD_FLAG).exists()) return null
        return try { FrameRecorder(File(appContext.filesDir, "live.bin")) } catch (e: java.io.IOException) {
            Log.w("XdeskDecoder", "không mở được tệp ghi luồng: ${e.message}")
            null
        }
    }

    fun trust(): ViewerTrust? = identity?.let { ViewerTrust(it, knownHosts) }
}

private const val RECORD_FLAG = "record-stream"

class XdeskApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        Log.i("XdeskCrypto", vn.xox.xdesk.crypto.CryptoDiagnostics.describe())
    }
}
