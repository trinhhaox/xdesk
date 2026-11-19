package vn.xox.xdesk.transport

enum class TransportErrorCode(val message: String) {
    CONNECTION_FAILED("Không kết nối được tới host"),
    CONNECTION_CLOSED("Host đã đóng kết nối"),
    TIMED_OUT("Hết thời gian chờ"),
    PROTOCOL_VIOLATION("Host gửi sai giao thức"),
    REJECTED("Host từ chối"),
    PAIRING_DENIED("Host không cho phép ghép đôi"),
    PAIRING_REQUIRED("Chưa ghép đôi với host này"),
    HOST_KEY_MISMATCH("Khoá của host không khớp (host cài lại hoặc bị mạo danh)"),
    RECONNECT_REFUSED("Host từ chối kết nối lại, có thể đã thu hồi thiết bị này"),
    REVOKED_BY_HOST("Host đã thu hồi thiết bị này"),
    NO_PEER("Chưa có kênh media"),
    LINK_LOST("Mất liên lạc với host (UDP)"),
}

/** Lỗi duy nhất của lớp vận chuyển. `reason` chỉ có với [TransportErrorCode.REJECTED] (lý do trong `reject`). */
class TransportException(
    val code: TransportErrorCode,
    val detail: String? = null,
    val reason: String? = null,
    cause: Throwable? = null,
) : Exception(if (detail == null) code.message else "${code.message}: $detail", cause)

internal fun transportError(code: TransportErrorCode, detail: String? = null, cause: Throwable? = null): Nothing =
    throw TransportException(code, detail, cause = cause)
