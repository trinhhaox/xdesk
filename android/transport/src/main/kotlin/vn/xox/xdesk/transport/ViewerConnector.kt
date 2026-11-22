package vn.xox.xdesk.transport

import vn.xox.xdesk.crypto.DeviceFingerprint
import vn.xox.xdesk.crypto.PairingURI

/** Cách viewer xác thực ở lần `connect` này. */
sealed interface ViewerAuth {
    /** Host đã ghép → IK; chưa ghép → `PAIRING_REQUIRED`; khoá đổi → `HOST_KEY_MISMATCH`. */
    object Automatic : ViewerAuth
    class Qr(val uri: PairingURI) : ViewerAuth
    /** So mã 6 số: `onCode` nhận [SasPrompt]; người dùng phải bấm "Khớp" ở cả viewer lẫn host. */
    class Sas(val onCode: (SasPrompt) -> Unit) : ViewerAuth
}

/** Kết quả bước kết nối + xác thực: kênh đã mã hoá, chưa hello/welcome. */
class ConnectedHost(
    val connection: ControlConnection, val target: ViewerTarget, val hostId: String,
    val hostKey: ByteArray, val hostName: String,
)

/** Mở TCP (thử lần lượt các địa chỉ), chọn kiểu bắt tay, ghi nhận host vào danh sách đã biết. */
class ViewerConnector(private val trust: ViewerTrust, private val deviceName: String, private val nowMs: () -> Long) {
    /** Host đã ghép vừa từ chối IK ở lần gần nhất (id = fingerprint); UI đề nghị "Ghép đôi lại". */
    @Volatile var refusedHostId: String? = null
        private set

    fun connect(candidates: List<ViewerTarget>, auth: ViewerAuth, timeoutMs: Int = 5000): ConnectedHost {
        refusedHostId = null
        val failures = mutableListOf<Pair<ViewerTarget, TransportException>>()
        for (target in candidates) {
            val conn = try {
                ControlConnection.connect(target.host, target.port, timeoutMs)
            } catch (e: TransportException) {
                failures += target to e
                continue
            }
            return authenticate(conn, target, auth)
        }
        throw connectFailure(failures)
    }

    private fun authenticate(conn: ControlConnection, target: ViewerTarget, auth: ViewerAuth): ConnectedHost {
        val mode = authMode(conn, target, auth)
        val outcome = try {
            InitiatorHandshake.run(conn, trust.identity, deviceName, mode)
        } catch (e: TransportException) {
            if (e.code == TransportErrorCode.RECONNECT_REFUSED && mode is ViewerAuthMode.Reconnect) {
                refusedHostId = DeviceFingerprint.make(mode.hostKey)
            }
            throw e
        }
        val id = DeviceFingerprint.make(outcome.hostKey)
        if (outcome.method != PairMethod.RECONNECT) trust.knownHosts.add(outcome.hostName, outcome.hostKey, nowMs())
        trust.knownHosts.markSeen(id, nowMs())
        trust.knownHosts.setLastAddress(id, target.address)
        return ConnectedHost(conn, target, id, outcome.hostKey, outcome.hostName)
    }

    private fun authMode(conn: ControlConnection, target: ViewerTarget, auth: ViewerAuth): ViewerAuthMode = when (auth) {
        is ViewerAuth.Qr -> ViewerAuthMode.Qr(auth.uri)
        is ViewerAuth.Sas -> ViewerAuthMode.Sas(auth.onCode)
        ViewerAuth.Automatic -> try {
            reconnectMode(target)
        } catch (e: TransportException) {
            conn.close()
            throw e
        }
    }

    private fun reconnectMode(target: ViewerTarget): ViewerAuthMode {
        val hostId = target.hostId
        if (hostId == null) {
            val known = trust.device(target.address) ?: transportError(TransportErrorCode.PAIRING_REQUIRED)
            return ViewerAuthMode.Reconnect(known.publicKey)
        }
        return when (val state = trust.state(hostId, target.name.orEmpty())) {
            is ViewerTrust.HostState.Paired -> ViewerAuthMode.Reconnect(state.host.publicKey)
            is ViewerTrust.HostState.KeyChanged -> transportError(TransportErrorCode.HOST_KEY_MISMATCH)
            ViewerTrust.HostState.Unknown -> transportError(TransportErrorCode.PAIRING_REQUIRED)
        }
    }

    /** Một địa chỉ: giữ nguyên lỗi. Nhiều địa chỉ: liệt kê từng địa chỉ đã thử để người dùng thấy cả LAN lẫn Tailscale. */
    private fun connectFailure(failures: List<Pair<ViewerTarget, TransportException>>): TransportException {
        if (failures.isEmpty()) return TransportException(TransportErrorCode.CONNECTION_FAILED, "không có địa chỉ")
        if (failures.size == 1) return failures[0].second
        val detail = failures.joinToString("; ") { (t, e) -> "${t.host}:${t.port} (${e.code.name.lowercase()})" }
        return TransportException(TransportErrorCode.CONNECTION_FAILED, "đã thử $detail")
    }
}
