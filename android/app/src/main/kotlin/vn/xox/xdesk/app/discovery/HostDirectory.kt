package vn.xox.xdesk.app.discovery

import vn.xox.xdesk.transport.KnownHost
import vn.xox.xdesk.transport.ViewerTarget

/** Một Mac đã ghép (từ kho tin cậy), kèm điểm cuối NSD nếu đang thấy trên mạng. */
data class PairedEntry(val known: KnownHost, val discovered: DiscoveredHost?) {
    val status: HostStatus = known.lastAddress.let { saved ->
        when {
            discovered != null -> HostStatus.Ready
            saved != null -> HostStatus.ViaAddress(saved)
            else -> HostStatus.NotSeen
        }
    }

    /** Thứ tự thử kết nối: điểm cuối NSD trước, rồi địa chỉ đã lưu (bỏ trùng). Rỗng = chưa có cách nào tới Mac này. */
    fun connectTargets(): List<ViewerTarget> {
        val saved = known.lastAddress?.let(ViewerTarget::parse)?.copy(hostId = known.id, name = known.name)
        return listOfNotNull(discovered?.toTarget(), saved).distinctBy { it.host to it.port }
    }
}

sealed interface HostStatus {
    val label: String

    object Ready : HostStatus { override val label = "Sẵn sàng" }
    data class ViaAddress(val address: String) : HostStatus { override val label = "Qua địa chỉ $address" }
    object NotSeen : HostStatus { override val label = "Không thấy trên mạng" }
}

/** Danh sách màn chính: mọi Mac đã ghép (không trùng theo fingerprint) và các Mac chưa ghép thấy trên mạng. */
data class HostDirectory(val paired: List<PairedEntry>, val others: List<DiscoveredHost>) {
    companion object {
        fun merge(known: List<KnownHost>, discovered: List<DiscoveredHost>): HostDirectory {
            val byId = discovered.distinctBy { it.id to it.host }.groupBy { it.id }
            val paired = known.map { PairedEntry(it, byId[it.id]?.first()) }
            val knownIds = known.mapTo(HashSet(), KnownHost::id)
            val others = discovered.filter { it.id !in knownIds }.distinctBy { it.id }
            return HostDirectory(paired, others)
        }
    }
}
