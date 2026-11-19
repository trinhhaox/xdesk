package vn.xox.xdesk.crypto

import java.util.Base64

/** Base64url không đệm (RFC 4648 §5) cho khoá/token trong QR. */
internal object Base64Url {
    fun encode(bytes: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

    /** `null` nếu có đệm `=`, ký tự lạ hoặc độ dài không hợp lệ. */
    fun decode(text: String): ByteArray? {
        if ('=' in text) return null
        return try { Base64.getUrlDecoder().decode(text) } catch (e: IllegalArgumentException) { null }
    }
}
