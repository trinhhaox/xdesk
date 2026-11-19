package vn.xox.xdesk.update

import vn.xox.xdesk.wire.json.JsonNumber
import vn.xox.xdesk.wire.json.JsonObject
import vn.xox.xdesk.wire.json.JsonParser
import vn.xox.xdesk.wire.json.JsonString
import vn.xox.xdesk.wire.json.JsonSyntaxException
import vn.xox.xdesk.wire.json.JsonValue

enum class UpdateFailure { MANIFEST_INVALID, INSECURE_URL, NETWORK, SIZE_MISMATCH, HASH_MISMATCH, SIGNATURE_MISMATCH }

/** Lỗi cập nhật có phân loại; `message` tiếng Việt, không bao giờ chứa URL. */
class UpdateException(val failure: UpdateFailure, message: String, cause: Throwable? = null) : Exception(message, cause)

/** `android-update.json` trên nhánh main của xdesk-releases. Mọi trường đều bắt buộc (releaseNotes có thể rỗng). */
data class UpdateManifest(
    val versionCode: Long,
    val versionName: String,
    val apkUrl: String,
    val sha256: String,
    val size: Long,
    val minSdk: Int,
    val releaseNotes: String,
    val publishedAt: String,
) {
    companion object {
        const val MAX_MANIFEST_BYTES = 64 * 1024
        const val MAX_APK_BYTES = 200L * 1024 * 1024
        private val SHA256_HEX = Regex("^[0-9a-f]{64}$")

        /** `requireHttps = false` chỉ để test với máy chủ loopback; app luôn dùng mặc định. */
        fun parse(bytes: ByteArray, requireHttps: Boolean = true): UpdateManifest {
            if (bytes.size > MAX_MANIFEST_BYTES) throw invalid("manifest quá lớn")
            val root = try { JsonParser.parse(bytes) } catch (e: JsonSyntaxException) {
                throw UpdateException(UpdateFailure.MANIFEST_INVALID, "Thông tin cập nhật không đọc được", e)
            }
            if (root !is JsonObject) throw invalid("gốc không phải đối tượng")
            val sha = root.string("sha256").lowercase()
            if (!SHA256_HEX.matches(sha)) throw invalid("sha256 sai định dạng")
            val apkUrl = root.string("apkUrl")
            if (requireHttps) requireHttps(apkUrl)
            val size = root.long("size")
            if (size <= 0 || size > MAX_APK_BYTES) throw invalid("size ngoài giới hạn")
            val versionCode = root.long("versionCode")
            val minSdk = root.long("minSdk")
            if (versionCode <= 0 || versionCode > Int.MAX_VALUE) throw invalid("versionCode không hợp lệ")
            if (minSdk <= 0 || minSdk > 1000) throw invalid("minSdk không hợp lệ")
            val versionName = root.string("versionName")
            if (versionName.isBlank()) throw invalid("versionName rỗng")
            return UpdateManifest(versionCode, versionName, apkUrl, sha, size, minSdk.toInt(), root.string("releaseNotes"), root.string("publishedAt"))
        }

        /** Chỉ chấp nhận `https://`; dùng cho cả manifest lẫn mọi bước chuyển hướng. */
        fun requireHttps(url: String) {
            if (!url.startsWith("https://", ignoreCase = true) || url.length <= "https://".length) {
                throw UpdateException(UpdateFailure.INSECURE_URL, "Địa chỉ cập nhật không dùng HTTPS")
            }
        }

        private fun invalid(why: String) = UpdateException(UpdateFailure.MANIFEST_INVALID, "Thông tin cập nhật không hợp lệ ($why)")

        private fun JsonObject.field(key: String): JsonValue = this[key] ?: throw invalid("thiếu $key")

        private fun JsonObject.string(key: String): String =
            when (val v = field(key)) { is JsonString -> v.value; else -> throw invalid("$key phải là chuỗi") }

        private fun JsonObject.long(key: String): Long =
            when (val v = field(key)) { is JsonNumber -> v.exactLong() ?: throw invalid("$key phải là số nguyên"); else -> throw invalid("$key phải là số") }
    }
}
