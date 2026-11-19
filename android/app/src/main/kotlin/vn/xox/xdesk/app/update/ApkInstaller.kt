package vn.xox.xdesk.app.update

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.os.Build
import java.io.File
import java.io.IOException

sealed interface InstallResult {
    data object Cancelled : InstallResult
    data class Failed(val message: String) : InstallResult
}

/**
 * Cài APK bằng PackageInstaller session (không dùng ACTION_VIEW). Khi thành công Android thay tiến trình app nên không có
 * callback thành công; mọi kết quả khác trả qua [onResult] trên main thread.
 */
class ApkInstaller(private val context: Context) {
    private val action = "${context.packageName}.UPDATE_INSTALL_RESULT"
    private var receiver: BroadcastReceiver? = null

    /** Ghi APK vào session rồi commit. APK nguồn có thể xoá ngay sau khi hàm này trả về (dữ liệu đã nằm trong session). */
    fun install(apk: File, onResult: (InstallResult) -> Unit) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setSize(apk.length())
            setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val id = installer.createSession(params)
        try {
            installer.openSession(id).use { session ->
                apk.inputStream().use { input ->
                    session.openWrite("xdesk.apk", 0, apk.length()).use { out ->
                        input.copyTo(out)
                        session.fsync(out)
                    }
                }
                listen(onResult)
                // FLAG_MUTABLE: hệ thống phải gắn thêm extras (trạng thái, intent xác nhận) vào broadcast.
                val pending = PendingIntent.getBroadcast(
                    context, id, Intent(action).setPackage(context.packageName), PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
                session.commit(pending.intentSender)
            }
        } catch (e: IOException) {
            stopListening()
            installer.abandonSession(id)
            throw e
        } catch (e: SecurityException) {
            stopListening()
            installer.abandonSession(id)
            throw IOException("Hệ thống từ chối phiên cài đặt", e)
        }
    }

    private fun listen(onResult: (InstallResult) -> Unit) {
        stopListening()
        val r = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
                    PackageInstaller.STATUS_PENDING_USER_ACTION -> confirmationIntent(intent)?.let {
                        it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        ctx.startActivity(it)
                    }
                    PackageInstaller.STATUS_SUCCESS -> stopListening()
                    PackageInstaller.STATUS_FAILURE_ABORTED -> { stopListening(); onResult(InstallResult.Cancelled) }
                    else -> { stopListening(); onResult(InstallResult.Failed(describe(intent))) }
                }
            }
        }
        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
        else context.registerReceiver(r, filter)
        receiver = r
    }

    private fun stopListening() {
        receiver?.let { runCatching { context.unregisterReceiver(it) } }
        receiver = null
    }

    @Suppress("DEPRECATION") // Overload không kiểu là cách duy nhất trước API 33.
    private fun confirmationIntent(intent: Intent): Intent? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_INTENT)

    private fun describe(intent: Intent): String = when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
        PackageInstaller.STATUS_FAILURE_BLOCKED -> "Hệ thống chặn việc cài đặt"
        PackageInstaller.STATUS_FAILURE_CONFLICT -> "Bản cài đặt xung đột với ứng dụng hiện tại"
        PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "Bản cập nhật không tương thích với thiết bị"
        PackageInstaller.STATUS_FAILURE_INVALID -> "Tệp cập nhật không hợp lệ"
        PackageInstaller.STATUS_FAILURE_STORAGE -> "Không đủ bộ nhớ để cài đặt"
        else -> intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "Cài đặt thất bại"
    }
}
