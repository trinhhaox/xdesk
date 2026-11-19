package vn.xox.xdesk.media

/** Mô tả một decoder đã được rút từ MediaCodecList (tách khỏi API Android để chọn lọc kiểm thử được trên JVM). */
data class CodecCandidate(
    val name: String,
    val isHardwareAccelerated: Boolean,
    val isSoftwareOnly: Boolean,
    val isAlias: Boolean,
    val supportsLowLatency: Boolean,
)

/**
 * Chọn decoder: ưu tiên phần cứng, tránh `OMX.google.*`/`c2.android.*` khi có phần cứng, ưu tiên hỗ trợ low-latency,
 * bỏ alias. Giữ nguyên thứ tự hệ thống khi điểm bằng nhau (thứ tự MediaCodecList đã phản ánh ưu tiên của hãng).
 */
object CodecSelector {
    fun select(candidates: List<CodecCandidate>): CodecCandidate? =
        candidates.filter { !it.isAlias }.ifEmpty { candidates }.withIndex()
            .sortedWith(compareByDescending<IndexedValue<CodecCandidate>> { score(it.value) }.thenBy { it.index })
            .firstOrNull()?.value

    private fun score(c: CodecCandidate): Int {
        var s = 0
        if (c.isHardwareAccelerated && !c.isSoftwareOnly) s += 100
        if (isGenericSoftware(c.name)) s -= 50
        if (c.supportsLowLatency) s += 10
        return s
    }

    fun isGenericSoftware(name: String): Boolean =
        name.startsWith("OMX.google.", ignoreCase = true) || name.startsWith("c2.android.", ignoreCase = true)
}
