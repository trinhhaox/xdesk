package vn.xox.xdesk.app

import android.app.Application
import android.content.Context
import java.io.File
import vn.xox.xdesk.app.identity.IdentityUnavailableException
import vn.xox.xdesk.app.identity.KeystoreIdentityStore
import vn.xox.xdesk.crypto.DeviceIdentity
import vn.xox.xdesk.crypto.IdentityStore
import vn.xox.xdesk.transport.FileKnownHostStore
import vn.xox.xdesk.transport.KnownHostStore
import vn.xox.xdesk.transport.ViewerTrust

/** Dựng tay các thành phần dùng chung (không DI framework: app nhỏ). Lưu trong [XdeskApplication]. */
class AppContainer(context: Context) {
    val identityStore: IdentityStore = KeystoreIdentityStore(File(context.filesDir, "identity.v1"))
    val knownHosts: KnownHostStore = FileKnownHostStore(File(context.filesDir, "known-hosts.txt"))

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

    fun trust(): ViewerTrust? = identity?.let { ViewerTrust(it, knownHosts) }
}

class XdeskApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
