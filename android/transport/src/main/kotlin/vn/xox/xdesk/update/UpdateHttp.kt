package vn.xox.xdesk.update

import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL

/** HTTP tối thiểu cho cập nhật: chỉ HTTPS (kể cả khi chuyển hướng), có timeout, giới hạn dung lượng, không ghi URL vào log/lỗi. */
class UpdateHttp(
    private val requireHttps: Boolean = true,
    private val connectTimeoutMs: Int = 10_000,
    private val readTimeoutMs: Int = 20_000,
) {
    fun fetchBytes(url: String, maxBytes: Int): ByteArray = request(url) { conn ->
        if (conn.contentLengthLong > maxBytes) throw tooLarge()
        val out = java.io.ByteArrayOutputStream()
        copyLimited(conn.inputStream, maxBytes.toLong()) { buf, n -> out.write(buf, 0, n) }
        out.toByteArray()
    }

    /** Tải vào `dest`; ném khi vượt `expectedSize`. Xoá tệp dở khi lỗi. `onProgress(đã tải, tổng)`. */
    fun download(url: String, dest: File, expectedSize: Long, onProgress: (Long, Long) -> Unit) {
        try {
            request(url) { conn ->
                if (conn.contentLengthLong > expectedSize) throw tooLarge()
                var total = 0L
                dest.outputStream().use { out ->
                    copyLimited(conn.inputStream, expectedSize) { buf, n ->
                        out.write(buf, 0, n)
                        total += n
                        onProgress(total, expectedSize)
                    }
                }
                if (total != expectedSize) throw UpdateException(UpdateFailure.SIZE_MISMATCH, "Tệp tải về sai kích thước")
            }
        } catch (e: Exception) {
            dest.delete()
            throw e
        }
    }

    private fun <T> request(url: String, handle: (HttpURLConnection) -> T): T {
        var current = url
        repeat(MAX_REDIRECTS + 1) {
            if (requireHttps) UpdateManifest.requireHttps(current)
            val conn = try { URL(current).openConnection() as? HttpURLConnection } catch (e: IOException) { null }
                ?: throw UpdateException(UpdateFailure.NETWORK, "Địa chỉ cập nhật không hợp lệ")
            conn.connectTimeout = connectTimeoutMs
            conn.readTimeout = readTimeoutMs
            conn.instanceFollowRedirects = false
            try {
                when (val code = conn.responseCode) {
                    HttpURLConnection.HTTP_OK -> return handle(conn)
                    301, 302, 303, 307, 308 -> {
                        val location = conn.getHeaderField("Location") ?: throw UpdateException(UpdateFailure.NETWORK, "Máy chủ chuyển hướng sai")
                        current = URI(current).resolve(location).toString()
                    }
                    else -> throw UpdateException(UpdateFailure.NETWORK, "Máy chủ trả mã $code")
                }
            } catch (e: IOException) {
                throw UpdateException(UpdateFailure.NETWORK, "Không kết nối được máy chủ cập nhật", e)
            } catch (e: java.net.URISyntaxException) {
                throw UpdateException(UpdateFailure.NETWORK, "Máy chủ chuyển hướng sai", e)
            } finally {
                conn.disconnect()
            }
        }
        throw UpdateException(UpdateFailure.NETWORK, "Quá nhiều lần chuyển hướng")
    }

    private fun copyLimited(input: InputStream, limit: Long, sink: (ByteArray, Int) -> Unit) {
        val buffer = ByteArray(32 * 1024)
        var total = 0L
        input.use {
            while (true) {
                val n = it.read(buffer)
                if (n < 0) break
                total += n
                if (total > limit) throw tooLarge()
                sink(buffer, n)
            }
        }
    }

    private fun tooLarge() = UpdateException(UpdateFailure.SIZE_MISMATCH, "Tệp cập nhật lớn hơn khai báo")

    private companion object { const val MAX_REDIRECTS = 5 }
}
