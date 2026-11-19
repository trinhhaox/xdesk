package vn.xox.xdesk.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import vn.xox.xdesk.transport.TransportErrorCode

enum class Screen { HOSTS, PAIR, STREAM, SECURITY }

/** Lỗi mà cách khắc phục là ghép đôi lại. */
internal val REPAIRABLE_CODES = setOf(
    TransportErrorCode.PAIRING_REQUIRED, TransportErrorCode.RECONNECT_REFUSED, TransportErrorCode.HOST_KEY_MISMATCH, TransportErrorCode.REVOKED_BY_HOST,
)

/**
 * Kết quả hiển thị của lần kết nối gần nhất. `message` là câu kỹ thuật gốc (hiện trong "Chi tiết"), `code` là mã lỗi vận chuyển nếu có,
 * `hostName` là tên máy Mac đang nối. `repairable` = nên đề nghị "Ghép đôi lại".
 */
data class ConnectionFailure(val message: String, val repairable: Boolean, val code: TransportErrorCode? = null, val hostName: String? = null)

/** Câu lỗi cho người dùng: `title` nói chuyện gì xảy ra, `hint` nói cách khắc phục; `warning` = lỗi cần cân nhắc (khoá đổi), không phải sự cố mạng. */
data class FailureText(val title: String, val hint: String, val warning: Boolean = false)

private val REFUSED = Regex("ECONNREFUSED|refused", RegexOption.IGNORE_CASE)
private val UNREACHABLE = Regex("EHOSTUNREACH|ENETUNREACH|unreachable|No route", RegexOption.IGNORE_CASE)
private val SLOW = Regex("ETIMEDOUT|timed out|timeout", RegexOption.IGNORE_CASE)

private fun noResponse(host: String) = FailureText("$host không phản hồi.", "Mac có thể đang ngủ hoặc ở mạng khác. Đánh thức Mac và kiểm tra cùng Wi-Fi.")

/** Đổi mã lỗi vận chuyển thành câu tiếng Việt: nguyên nhân và cách khắc phục. Không có mã (địa chỉ sai, lỗi giải mã) thì giữ câu gốc. */
fun ConnectionFailure.describe(): FailureText {
    val host = hostName?.takeIf { it.isNotBlank() } ?: "máy Mac"
    return when (code) {
        TransportErrorCode.TIMED_OUT -> noResponse(host)
        TransportErrorCode.CONNECTION_FAILED -> when {
            REFUSED.containsMatchIn(message) -> FailureText("$host không nhận kết nối.", "Mở Xdesk trên Mac, và kiểm tra Xdesk không bị tường lửa chặn.")
            UNREACHABLE.containsMatchIn(message) -> FailureText("Không tìm thấy $host trên mạng này.", "Điện thoại và Mac cần cùng Wi-Fi (hoặc cùng Tailscale). Kiểm tra địa chỉ rồi thử lại.")
            SLOW.containsMatchIn(message) -> noResponse(host)
            else -> FailureText("Không kết nối được tới $host.", "Kiểm tra điện thoại và Mac cùng một mạng Wi-Fi rồi thử lại.")
        }
        TransportErrorCode.CONNECTION_CLOSED -> FailureText("$host đã ngắt kết nối.", "Mở lại Xdesk trên Mac rồi thử lại.")
        TransportErrorCode.PROTOCOL_VIOLATION -> FailureText("Xdesk trên $host không tương thích.", "Cập nhật Xdesk trên cả hai máy lên bản mới nhất.")
        TransportErrorCode.REJECTED -> FailureText("$host từ chối kết nối.", "Mở Xdesk trên Mac và cho phép thiết bị này.")
        TransportErrorCode.PAIRING_DENIED -> FailureText("$host không cho phép ghép đôi.", "Trên Mac, bật ghép đôi thiết bị mới rồi thử lại.")
        TransportErrorCode.PAIRING_REQUIRED -> FailureText("Điện thoại chưa ghép đôi với $host.", "Bấm Ghép đôi lại, rồi quét QR hoặc so mã 6 số.")
        TransportErrorCode.HOST_KEY_MISMATCH -> FailureText(
            "Khoá bảo mật của $host đã đổi.", "Mac có thể đã cài lại Xdesk. Chỉ ghép đôi lại nếu chắc đây đúng máy của bạn.", warning = true,
        )
        TransportErrorCode.RECONNECT_REFUSED -> FailureText("$host không nhận lại điện thoại này.", "Có thể thiết bị đã bị gỡ khỏi Mac. Ghép đôi lại để dùng tiếp.")
        TransportErrorCode.REVOKED_BY_HOST -> FailureText("$host đã thu hồi quyền của điện thoại này.", "Ghép đôi lại nếu bạn muốn dùng tiếp.")
        TransportErrorCode.NO_PEER -> FailureText("Chưa mở được kênh hình ảnh tới $host.", "Thử lại; nếu vẫn lỗi, khởi động lại Xdesk trên Mac.")
        TransportErrorCode.LINK_LOST -> FailureText("Mất liên lạc với $host.", "Kiểm tra Wi-Fi của cả hai máy rồi thử lại.")
        null -> FailureText(message, "Kiểm tra lại rồi thử lại.")
    }
}

/** Câu kỹ thuật chỉ đáng hiện trong "Chi tiết" khi nó khác câu đã hiển thị. */
fun ConnectionFailure.technicalDetail(): String? = message.takeIf { code != null && it.isNotBlank() }

/** Kết quả một lần ghép đôi, phát một lần để rung phản hồi (CONFIRM / REJECT). */
class PairingResult(val success: Boolean)

/** Trạng thái tiến trình kết nối cho giao diện; chỉ ghi từ main thread. */
class ConnectionProgress {
    var targetName by mutableStateOf("")
    /** Đã có khung hình đầu tiên giải mã được; trước đó vẫn hiện lớp phủ kết nối. */
    var frameShown by mutableStateOf(false)
    /** Kết quả ghép đôi gần nhất; mỗi lần là một đối tượng mới để giao diện rung đúng một lần. */
    var pairingResult by mutableStateOf<PairingResult?>(null)
        private set
    private var pairing = false

    fun begin(isPairing: Boolean) { frameShown = false; pairing = isPairing }

    fun finish(success: Boolean) {
        if (pairing) pairingResult = PairingResult(success)
        pairing = false
    }
}
