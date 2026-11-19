package vn.xox.xdesk.transport

import vn.xox.xdesk.crypto.DeviceIdentity

/** Đích kết nối: host tìm thấy qua NSD (`hostId` = TXT `id`) hoặc nhập tay `host:port` (`hostId` = null). */
data class ViewerTarget(val host: String, val port: Int, val hostId: String? = null, val name: String? = null) {
    val address: String get() = if (':' in host) "[$host]:$port" else "$host:$port"

    companion object {
        /** `host:port` hoặc `[IPv6]:port`; sai định dạng → `null`. */
        fun parse(text: String): ViewerTarget? {
            val t = text.trim()
            val host: String
            val portText: String
            if (t.startsWith("[")) {
                val close = t.indexOf(']')
                if (close < 0 || !t.startsWith(":", close + 1)) return null
                host = t.substring(1, close)
                portText = t.substring(close + 2)
            } else {
                val parts = t.split(':')
                if (parts.size != 2) return null
                host = parts[0]
                portText = parts[1]
            }
            val port = portText.toIntOrNull()?.takeIf { it in 1..65535 } ?: return null
            return if (host.isEmpty()) null else ViewerTarget(host, port)
        }
    }
}

/** Danh tính viewer + danh sách host đã biết. */
class ViewerTrust(val identity: DeviceIdentity, val knownHosts: KnownHostStore) {
    sealed interface HostState {
        /** Fingerprint NSD khớp host đã ghép → IK. */
        class Paired(val host: KnownHost) : HostState
        object Unknown : HostState

        /** Cùng tên NSD với host đã ghép nhưng fingerprint khác: cài lại hoặc mạo danh → cảnh báo, không kết nối. */
        class KeyChanged(val expected: KnownHost) : HostState
    }

    fun state(hostId: String, name: String): HostState {
        val known = knownHosts.all()
        known.firstOrNull { it.id == hostId }?.let { return HostState.Paired(it) }
        known.firstOrNull { it.name == name }?.let { return HostState.KeyChanged(it) }
        return HostState.Unknown
    }

    /** Host đã ghép từng kết nối thành công tại `host:port` (nhập tay). */
    fun device(address: String): KnownHost? = knownHosts.all().firstOrNull { it.lastAddress == address }
}
