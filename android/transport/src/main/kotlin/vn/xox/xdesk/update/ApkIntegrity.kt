package vn.xox.xdesk.update

import java.io.File
import java.security.MessageDigest

/** Kiểm tra APK đã tải: kích thước, SHA-256 và so khớp chứng chỉ ký. */
object ApkIntegrity {
    fun sha256Hex(file: File): String = file.inputStream().use { input ->
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val n = input.read(buffer)
            if (n < 0) break
            digest.update(buffer, 0, n)
        }
        hex(digest.digest())
    }

    fun certSha256Hex(encodedCert: ByteArray): String = hex(MessageDigest.getInstance("SHA-256").digest(encodedCert))

    fun verify(file: File, manifest: UpdateManifest) {
        if (file.length() != manifest.size) throw UpdateException(UpdateFailure.SIZE_MISMATCH, "Tệp tải về sai kích thước")
        val actual = sha256Hex(file).toByteArray(Charsets.US_ASCII)
        if (!MessageDigest.isEqual(actual, manifest.sha256.toByteArray(Charsets.US_ASCII))) {
            throw UpdateException(UpdateFailure.HASH_MISMATCH, "Tệp tải về sai mã SHA-256")
        }
    }

    /** Hai tập chứng chỉ phải giống hệt nhau và không rỗng. */
    fun signersMatch(installed: Set<String>, candidate: Set<String>): Boolean = installed.isNotEmpty() && installed == candidate

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }
}
