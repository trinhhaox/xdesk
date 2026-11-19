package vn.xox.xdesk.update

/** Nơi nhớ mốc kiểm tra gần nhất (SharedPreferences ở app, bộ nhớ trong test). */
interface LastCheckStore {
    var lastCheckMs: Long?
}

sealed interface CheckOutcome {
    /** Chưa đủ 24 giờ kể từ lần trước (chỉ khi kiểm tra tự động). */
    data object Throttled : CheckOutcome
    data object UpToDate : CheckOutcome
    data class Available(val manifest: UpdateManifest) : CheckOutcome
    data class Failed(val error: UpdateException) : CheckOutcome
}

/** Tải manifest, so phiên bản. `fetch(url, maxBytes)` được tiêm vào để test không cần mạng. */
class UpdateChecker(
    private val manifestUrl: String,
    private val fetch: (String, Int) -> ByteArray,
    private val store: LastCheckStore,
    private val nowMs: () -> Long,
    private val installedVersionCode: Long,
    private val deviceSdk: Int,
    private val requireHttps: Boolean = true,
) {
    /** `manual = true` bỏ qua giới hạn 24 giờ. Chỉ ghi mốc khi lấy và đọc manifest thành công. */
    fun check(manual: Boolean): CheckOutcome {
        if (!manual && !UpdatePolicy.shouldCheck(store.lastCheckMs, nowMs())) return CheckOutcome.Throttled
        val manifest = try {
            UpdateManifest.parse(fetch(manifestUrl, UpdateManifest.MAX_MANIFEST_BYTES), requireHttps)
        } catch (e: UpdateException) {
            return CheckOutcome.Failed(e)
        }
        store.lastCheckMs = nowMs()
        return if (UpdatePolicy.isApplicable(manifest, installedVersionCode, deviceSdk)) CheckOutcome.Available(manifest) else CheckOutcome.UpToDate
    }
}
