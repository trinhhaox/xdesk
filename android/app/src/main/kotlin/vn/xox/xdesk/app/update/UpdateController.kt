package vn.xox.xdesk.app.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import vn.xox.xdesk.update.ApkIntegrity
import vn.xox.xdesk.update.CheckOutcome
import vn.xox.xdesk.update.LastCheckStore
import vn.xox.xdesk.update.UpdateChecker
import vn.xox.xdesk.update.UpdateFailure
import vn.xox.xdesk.update.UpdateException
import vn.xox.xdesk.update.UpdateHttp
import vn.xox.xdesk.update.UpdateManifest

sealed interface UpdateState {
    data object Idle : UpdateState
    data object Checking : UpdateState
    data object UpToDate : UpdateState
    data class Available(val manifest: UpdateManifest) : UpdateState
    /** Đang có phiên stream: giữ bản cập nhật lại, không tải/cài. */
    data class Deferred(val manifest: UpdateManifest) : UpdateState
    data class Downloading(val manifest: UpdateManifest, val percent: Int) : UpdateState
    data class Installing(val manifest: UpdateManifest) : UpdateState
    /** Chưa cấp "Cài ứng dụng không rõ nguồn" cho Xdesk. */
    data class NeedsPermission(val manifest: UpdateManifest) : UpdateState
    /** `downloadUrl`: có khi cần gỡ app rồi cài tay bản chính thức (bản đang cài ký khác bản phát hành). */
    data class Failed(val message: String, val downloadUrl: String? = null) : UpdateState
}

/** Điều phối kiểm tra, tải, xác minh và cài đặt. Trạng thái Compose chỉ ghi từ main thread; mạng chạy trên một thread nền. */
class UpdateController(private val context: Context, private val manifestUrl: String = MANIFEST_URL) {
    private val main = Handler(Looper.getMainLooper())
    private val background = Executors.newSingleThreadExecutor { Thread(it, "xdesk-update") }
    private val http = UpdateHttp()
    private val installer = ApkInstaller(context)
    private val prefs = context.getSharedPreferences("update", Context.MODE_PRIVATE)
    private val updateDir = File(context.cacheDir, "updates")
    private var dismissedVersionCode = 0L

    /** Do UI đặt: true khi đang kết nối/stream để hoãn tải và cài. */
    var isSessionActive: () -> Boolean = { false }

    var state by mutableStateOf<UpdateState>(UpdateState.Idle)
        private set

    @Suppress("DEPRECATION") // longVersionCode có từ API 28; versionName đủ cho hiển thị.
    private val installed = context.packageManager.getPackageInfo(context.packageName, 0)
    val installedVersionName: String = installed.versionName.orEmpty()
    val installedVersionCode: Long = installed.longVersionCode

    init {
        // Tiến trình bị thay khi cài thành công nên bản APK còn sót (nếu có) được dọn ở lần mở sau.
        background.execute { updateDir.deleteRecursively() }
    }

    /** Lúc mở app: tối đa một lần mỗi 24 giờ, không làm phiền khi đang stream, im lặng khi lỗi mạng. */
    fun checkOnStart() {
        if (isSessionActive()) return
        runCheck(manual = false)
    }

    fun checkNow() = runCheck(manual = true)

    private fun runCheck(manual: Boolean) {
        if (state is UpdateState.Checking || state is UpdateState.Downloading || state is UpdateState.Installing) return
        val previous = state
        if (manual) state = UpdateState.Checking
        val checker = UpdateChecker(manifestUrl, http::fetchBytes, PrefsStore(), System::currentTimeMillis, installedVersionCode, Build.VERSION.SDK_INT)
        background.execute {
            val outcome = checker.check(manual)
            main.post { onCheckResult(outcome, manual, previous) }
        }
    }

    private fun onCheckResult(outcome: CheckOutcome, manual: Boolean, previous: UpdateState) {
        state = when (outcome) {
            CheckOutcome.Throttled -> previous
            CheckOutcome.UpToDate -> if (manual) UpdateState.UpToDate else previous
            is CheckOutcome.Available ->
                if (!manual && outcome.manifest.versionCode == dismissedVersionCode) previous else UpdateState.Available(outcome.manifest)
            is CheckOutcome.Failed -> if (manual) UpdateState.Failed(outcome.error.message.orEmpty()) else previous
        }
    }

    /** "Để sau": ẩn hộp thoại; lần kiểm tra tự động sau không nhắc lại đúng phiên bản này trong lần chạy hiện tại. */
    fun dismiss() {
        dismissedVersionCode = when (val s = state) {
            is UpdateState.Available -> s.manifest.versionCode
            is UpdateState.Deferred -> s.manifest.versionCode
            is UpdateState.NeedsPermission -> s.manifest.versionCode
            else -> dismissedVersionCode
        }
        state = UpdateState.Idle
    }

    fun install(manifest: UpdateManifest) {
        if (isSessionActive()) { state = UpdateState.Deferred(manifest); return }
        if (!context.packageManager.canRequestPackageInstalls()) { state = UpdateState.NeedsPermission(manifest); return }
        state = UpdateState.Downloading(manifest, 0)
        background.execute { downloadVerifyInstall(manifest) }
    }

    /** Mở link tải APK chính thức bằng trình duyệt (khi phải gỡ bản đang cài rồi cài tay). */
    fun openDownload(url: String) {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        state = UpdateState.Idle
    }

    /** Mở trang "Cài ứng dụng không rõ nguồn" của chính Xdesk. */
    fun openUnknownSourcesSettings() {
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    private fun downloadVerifyInstall(manifest: UpdateManifest) {
        val apk = File(updateDir, "xdesk-update.apk")
        try {
            updateDir.mkdirs()
            var lastPercent = -1
            http.download(manifest.apkUrl, apk, manifest.size) { done, total ->
                val percent = (done * 100 / total).toInt()
                if (percent != lastPercent) { lastPercent = percent; main.post { state = UpdateState.Downloading(manifest, percent) } }
            }
            ApkIntegrity.verify(apk, manifest)
            ApkSignatures.verifyMatchesInstalled(context, apk, manifest.versionCode)
            main.post { commit(manifest, apk) }
        } catch (e: UpdateException) {
            apk.delete()
            val failed = if (e.failure == UpdateFailure.SIGNATURE_MISMATCH) {
                UpdateState.Failed(SIGNATURE_MISMATCH_HELP, manifest.apkUrl)
            } else UpdateState.Failed(e.message.orEmpty())
            main.post { state = failed }
        } catch (e: IOException) {
            apk.delete()
            main.post { state = UpdateState.Failed("Không ghi được tệp cập nhật") }
        }
    }

    /** Chạy trên main: kiểm tra lại phiên stream (tải có thể mất lâu), rồi giao APK cho PackageInstaller và xoá tệp tạm. */
    private fun commit(manifest: UpdateManifest, apk: File) {
        if (isSessionActive()) { apk.delete(); state = UpdateState.Deferred(manifest); return }
        state = UpdateState.Installing(manifest)
        try {
            installer.install(apk) { result ->
                state = when (result) {
                    InstallResult.Cancelled -> UpdateState.Available(manifest)
                    is InstallResult.Failed -> UpdateState.Failed(result.message)
                }
            }
        } catch (e: IOException) {
            state = UpdateState.Failed("Không bắt đầu được cài đặt")
        } finally {
            apk.delete()
        }
    }

    private inner class PrefsStore : LastCheckStore {
        override var lastCheckMs: Long?
            get() = if (prefs.contains(KEY_LAST_CHECK)) prefs.getLong(KEY_LAST_CHECK, 0) else null
            set(value) { prefs.edit().apply { if (value == null) remove(KEY_LAST_CHECK) else putLong(KEY_LAST_CHECK, value) }.apply() }
    }

    companion object {
        const val MANIFEST_URL = "https://raw.githubusercontent.com/trinhhaox/xdesk-releases/main/android-update.json"
        private const val KEY_LAST_CHECK = "last_check_ms"
        private const val SIGNATURE_MISMATCH_HELP = "Xdesk trên máy này là bản dựng thử (ký khác bản phát hành) nên không cập nhật đè được. " +
            "Hãy gỡ Xdesk rồi cài bản chính thức; sau đó ghép đôi lại với Mac. Từ bản chính thức trở đi, cập nhật sẽ tự chạy."
    }
}
