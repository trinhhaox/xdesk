package vn.xox.xdesk.media

/** Hành vi riêng của một họ decoder, tra theo tiền tố tên codec (xem [DecoderQuirks.forCodec]). */
data class DecoderQuirk(
    /** Tiền tố tên codec (không phân biệt hoa/thường). */
    val namePrefix: String,
    /** Khoá MediaFormat riêng của hãng để bật chế độ giải mã độ trễ thấp (giá trị int). */
    val lowLatencyKeys: Map<String, Int> = emptyMap(),
    /** Decoder hay giữ vài frame trước khi xuất (đo bằng [FrameLagMeter]); cần cảnh báo/ghi log khi lag vượt ngưỡng. */
    val mayHoldFrames: Boolean = false,
    /** Nhét cờ `KEY_MAX_INPUT_SIZE` lớn hơn để không bị cắt keyframe lớn. */
    val maxInputSizeBytes: Int? = null,
)

/**
 * Bảng quirk theo tên codec. Các khoá hãng là khoá công khai trong các bản Codec2/OMX của Qualcomm/Exynos;
 * chưa kiểm chứng trên thiết bị JP1 (xem ghi chú phase 07b): decoder không nhận khoá lạ thì bỏ qua, không lỗi.
 */
object DecoderQuirks {
    private val table = listOf(
        DecoderQuirk("c2.qti", mapOf("vendor.qti-ext-dec-low-latency.enable" to 1)),
        DecoderQuirk("OMX.qcom", mapOf("vendor.qti-ext-dec-low-latency.enable" to 1)),
        DecoderQuirk("c2.exynos", mapOf("vendor.rtc-ext-dec-low-latency.enable" to 1)),
        DecoderQuirk("OMX.Exynos", mapOf("vendor.rtc-ext-dec-low-latency.enable" to 1)),
        DecoderQuirk("c2.mtk", mayHoldFrames = true),
        DecoderQuirk("OMX.MTK", mayHoldFrames = true),
        DecoderQuirk("c2.unisoc", mayHoldFrames = true),
        DecoderQuirk("OMX.sprd", mayHoldFrames = true),
        DecoderQuirk("OMX.google", maxInputSizeBytes = 2 shl 20),
        DecoderQuirk("c2.android", maxInputSizeBytes = 2 shl 20),
    )

    /** Quirk đầu tiên có tiền tố khớp; `null` nếu không có. */
    fun forCodec(name: String): DecoderQuirk? = table.firstOrNull { name.startsWith(it.namePrefix, ignoreCase = true) }
}
