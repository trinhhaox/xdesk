package vn.xox.xdesk.update

/** Quy tắc thuần: có nên kiểm tra không và bản trong manifest có áp dụng được không. */
object UpdatePolicy {
    const val CHECK_INTERVAL_MS = 24L * 60 * 60 * 1000

    /** Chỉ nhận versionCode cao hơn hẳn bản đang cài, và máy phải đủ minSdk. */
    fun isApplicable(manifest: UpdateManifest, installedVersionCode: Long, deviceSdk: Int): Boolean =
        manifest.versionCode > installedVersionCode && deviceSdk >= manifest.minSdk

    /** Tối đa một lần mỗi 24 giờ. Mốc nằm ở tương lai (đồng hồ bị lùi) coi như hỏng nên kiểm tra lại. */
    fun shouldCheck(lastCheckMs: Long?, nowMs: Long, intervalMs: Long = CHECK_INTERVAL_MS): Boolean {
        if (lastCheckMs == null) return true
        val elapsed = nowMs - lastCheckMs
        return elapsed < 0 || elapsed >= intervalMs
    }
}
