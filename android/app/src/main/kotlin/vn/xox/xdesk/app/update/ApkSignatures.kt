package vn.xox.xdesk.app.update

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import vn.xox.xdesk.update.ApkIntegrity
import vn.xox.xdesk.update.UpdateException
import vn.xox.xdesk.update.UpdateFailure

/** So chứng chỉ ký của APK tải về với chứng chỉ của chính app đang cài; khác thì từ chối. */
object ApkSignatures {
    fun verifyMatchesInstalled(context: Context, apk: File, expectedVersionCode: Long) {
        val pm = context.packageManager
        val archive = archiveInfo(pm, apk) ?: throw mismatch("Tệp cập nhật không phải APK hợp lệ hoặc chưa ký")
        if (archive.packageName != context.packageName) throw mismatch("Tệp cập nhật thuộc ứng dụng khác")
        if (archive.longVersionCode != expectedVersionCode) throw mismatch("Phiên bản trong tệp không khớp thông tin cập nhật")
        val installed = installedInfo(pm, context.packageName) ?: throw mismatch("Không đọc được chữ ký ứng dụng đang cài")
        if (!ApkIntegrity.signersMatch(signerHashes(installed), signerHashes(archive))) {
            throw mismatch("Chữ ký của bản cập nhật khác chữ ký ứng dụng đang cài")
        }
    }

    private fun signerHashes(info: PackageInfo): Set<String> =
        info.signingInfo?.apkContentsSigners.orEmpty().map { ApkIntegrity.certSha256Hex(it.toByteArray()) }.toSet()

    @Suppress("DEPRECATION") // Overload Int là cách duy nhất trên API 31-32.
    private fun archiveInfo(pm: PackageManager, apk: File): PackageInfo? =
        if (Build.VERSION.SDK_INT >= 33) pm.getPackageArchiveInfo(apk.path, PackageManager.PackageInfoFlags.of(FLAGS.toLong()))
        else pm.getPackageArchiveInfo(apk.path, FLAGS)

    @Suppress("DEPRECATION")
    private fun installedInfo(pm: PackageManager, packageName: String): PackageInfo? = try {
        if (Build.VERSION.SDK_INT >= 33) pm.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(FLAGS.toLong()))
        else pm.getPackageInfo(packageName, FLAGS)
    } catch (e: PackageManager.NameNotFoundException) {
        null
    }

    private fun mismatch(message: String) = UpdateException(UpdateFailure.SIGNATURE_MISMATCH, message)

    private const val FLAGS = PackageManager.GET_SIGNING_CERTIFICATES
}
