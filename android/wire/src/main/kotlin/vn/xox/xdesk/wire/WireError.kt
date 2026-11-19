package vn.xox.xdesk.wire

/** Mã lỗi giải mã/mã hoá, trùng tên với `WireError.code` của bản Swift và với test vectors. */
enum class WireErrorCode {
    truncated,
    invalidFrameLength,
    frameTooLarge,
    unknownFrameKind,
    unsupportedVersion,
    unknownPacketType,
    unexpectedPacketType,
    invalidFragment,
    fragmentCountTooLarge,
    inconsistentFragmentCount,
    payloadTooLarge,
    emptyPayload,
    invalidNackCount,
    invalidInput,
    malformedJSON,
    invalidField,
}

/** Lỗi duy nhất mà mọi bộ giải mã của module `wire` được phép ném. */
class WireException(val code: WireErrorCode, detail: String = "") :
    Exception(if (detail.isEmpty()) code.name else "${code.name}: $detail")

internal fun wireError(code: WireErrorCode, detail: String = ""): Nothing = throw WireException(code, detail)
