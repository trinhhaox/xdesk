package vn.xox.xdesk.app.discovery

import vn.xox.xdesk.transport.ViewerTarget
import vn.xox.xdesk.transport.ViewerTrust

/** Host tìm thấy qua NSD `_xdesk._tcp`; `id` là TXT `id` (fingerprint ngắn), `name` là TXT `n` (hoặc tên dịch vụ). */
data class DiscoveredHost(val id: String, val name: String, val host: String, val port: Int) {
    fun toTarget() = ViewerTarget(host, port, hostId = id, name = name)
}

/** Nhãn trạng thái ghép của host trong danh sách. */
enum class HostBadge(val label: String) {
    PAIRED("Đã ghép"), UNPAIRED("Chưa ghép"), KEY_CHANGED("Khoá đã đổi");

    companion object {
        fun of(host: DiscoveredHost, trust: ViewerTrust): HostBadge = when (trust.state(host.id, host.name)) {
            is ViewerTrust.HostState.Paired -> PAIRED
            is ViewerTrust.HostState.KeyChanged -> KEY_CHANGED
            ViewerTrust.HostState.Unknown -> UNPAIRED
        }
    }
}
