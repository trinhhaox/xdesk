package vn.xox.xdesk.transport

/** Theo dõi sức khoẻ đường UDP mỗi giây: keepalive, xin đồng bộ epoch khi chỉ thấy `unknownEpoch`, báo mất liên lạc. */
internal class LinkHealth(private val nowMs: () -> Long) {
    var unknownEpochCount = 0
    private var lastValidMs = nowMs()
    private var lastMaintainMs = 0L
    private var lastKeepaliveMs = 0L
    private var lastResyncAskMs = 0L
    private var linkLostReported = false

    /** Có một gói hợp lệ vừa xác thực. */
    fun markValid() {
        lastValidMs = nowMs()
        unknownEpochCount = 0
        linkLostReported = false
    }

    fun maintain(heardFromHost: Boolean, sendProbe: () -> Unit, askResync: () -> Unit, onLinkLost: () -> Unit) {
        val now = nowMs()
        if (now - lastMaintainMs < 1000) return
        lastMaintainMs = now
        if (heardFromHost && now - lastKeepaliveMs >= KEEPALIVE_INTERVAL_MS) {
            lastKeepaliveMs = now
            sendProbe()
        }
        if (unknownEpochCount >= 3 && now - lastValidMs >= 2000 && now - lastResyncAskMs >= 5000) {
            lastResyncAskMs = now
            askResync()
        }
        if (now - lastValidMs >= LINK_TIMEOUT_MS && !linkLostReported) {
            linkLostReported = true
            onLinkLost()
        }
    }

    companion object {
        const val KEEPALIVE_INTERVAL_MS = 2000L
        const val LINK_TIMEOUT_MS = 10_000L
    }
}
