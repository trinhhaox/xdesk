package vn.xox.xdesk.media

/** Cấu hình decoder đang chạy: cùng Surface (so theo tham chiếu) + cỡ + khoá phụ + mime thì không cần dựng lại. */
internal data class DecoderKey(val surface: Any, val width: Int, val height: Int, val extra: Map<String, Int>, val mime: String = AndroidCodecList.MIME_AVC)

/** Việc phải làm khi có yêu cầu start mới. */
internal enum class StartPlan { SKIP_NO_SURFACE, SKIP_UNCHANGED, START, RESTART }

internal object DecoderLifecycle {
    /**
     * Không bao giờ configure khi Surface đã chết; không dựng lại khi yêu cầu trùng cấu hình đang chạy
     * (surfaceChanged bắn nhiều lần); còn codec cũ thì phải huỷ trước, vì Surface chỉ nối được với một codec.
     */
    fun plan(active: DecoderKey?, requested: DecoderKey, surfaceValid: Boolean): StartPlan = when {
        !surfaceValid -> StartPlan.SKIP_NO_SURFACE
        active == null -> StartPlan.START
        active == requested -> StartPlan.SKIP_UNCHANGED
        else -> StartPlan.RESTART
    }

    /** Mô tả lỗi không bao giờ ra "null": lớp ngoại lệ + message (nếu có) + chi tiết riêng của codec (diagnosticInfo, errorCode). */
    fun describe(e: Throwable, codecDetail: String? = null): String {
        val parts = listOfNotNull(e.message?.takeIf { it.isNotBlank() }, codecDetail?.takeIf { it.isNotBlank() })
        return if (parts.isEmpty()) e.javaClass.simpleName else "${e.javaClass.simpleName}: ${parts.joinToString(", ")}"
    }
}
