package vn.xox.xdesk.transport

import java.security.MessageDigest
import vn.xox.xdesk.crypto.DeviceIdentity
import vn.xox.xdesk.crypto.DeviceRole
import vn.xox.xdesk.crypto.HandshakeFrame
import vn.xox.xdesk.crypto.HandshakePayload
import vn.xox.xdesk.crypto.NoiseHandshakeState
import vn.xox.xdesk.crypto.NoisePattern
import vn.xox.xdesk.crypto.NoiseRole
import vn.xox.xdesk.crypto.PairingURI
import vn.xox.xdesk.crypto.ShortAuthString
import vn.xox.xdesk.crypto.sessionKeys
import vn.xox.xdesk.wire.ControlMessage

/** Cách viewer xác thực với host. */
sealed interface ViewerAuthMode {
    /** IK: biết khoá host đã ghép. */
    class Reconnect(val hostKey: ByteArray) : ViewerAuthMode

    /** XXpsk3: quét QR; khoá host trong QR được ghim trước khi gửi message 3. */
    class Qr(val uri: PairingURI) : ViewerAuthMode

    /** XX + SAS: `onCode` nhận "NNN NNN" trong lúc chờ host bấm "Khớp"; phải trả về ngay (không chặn). */
    class Sas(val onCode: (String) -> Unit) : ViewerAuthMode
}

enum class PairMethod { RECONNECT, QR_PAIRED, SAS_PAIRED }

class InitiatorOutcome(val hostKey: ByteArray, val hostName: String, val method: PairMethod)

/** Bắt tay Noise phía viewer (initiator). Xong thì kênh đã mã hoá; tiếp tục bằng [ViewerHandshake]. */
object InitiatorHandshake {
    const val MESSAGE_TIMEOUT_MS = 5_000
    const val PAIRING_DECISION_TIMEOUT_MS = 120_000

    /**
     * IK mà host đóng im lặng (đóng sạch hoặc reset) → [TransportErrorCode.RECONNECT_REFUSED]; không tự xoá host,
     * UI đề nghị "Ghép đôi lại".
     */
    fun run(conn: ControlConnection, identity: DeviceIdentity, deviceName: String, mode: ViewerAuthMode): InitiatorOutcome {
        val outcome = try {
            runNoise(conn, identity, deviceName, mode)
        } catch (e: TransportException) {
            conn.close()
            val silent = e.code == TransportErrorCode.CONNECTION_CLOSED || e.code == TransportErrorCode.CONNECTION_FAILED
            if (mode is ViewerAuthMode.Reconnect && silent) transportError(TransportErrorCode.RECONNECT_REFUSED, cause = e)
            throw e
        } catch (e: Exception) {
            conn.close()
            throw e
        }
        if (mode !is ViewerAuthMode.Reconnect) awaitPairingResult(conn)
        return outcome
    }

    private fun runNoise(conn: ControlConnection, identity: DeviceIdentity, deviceName: String, mode: ViewerAuthMode): InitiatorOutcome {
        val pattern = when (mode) {
            is ViewerAuthMode.Reconnect -> NoisePattern.IK
            is ViewerAuthMode.Qr -> NoisePattern.XX_PSK3
            is ViewerAuthMode.Sas -> NoisePattern.XX
        }
        val hostKeyHint = (mode as? ViewerAuthMode.Reconnect)?.hostKey
        // NoiseHandshakeState giữ tham chiếu tới mảng khoá riêng (không copy): không được xoá mảng trước khi bắt tay xong.
        val state = NoiseHandshakeState(
            pattern, NoiseRole.INITIATOR, identity.privateKey(), hostKeyHint, (mode as? ViewerAuthMode.Qr)?.uri?.token,
        )
        conn.sendHandshake(HandshakeFrame.Begin(pattern))
        val nonce = ShortAuthString.randomNonce()
        val hello = if (pattern == NoisePattern.IK) HandshakePayload(DeviceRole.VIEWER, deviceName).encode() else ByteArray(0)
        val message1 = state.writeMessage(hello)
        val ephemeral = state.localEphemeralKey
        if (pattern == NoisePattern.XX && ephemeral != null) {
            conn.sendHandshake(HandshakeFrame.Commit(ShortAuthString.commitment(ephemeral, identity.publicKey, nonce)))
        }
        conn.sendHandshake(HandshakeFrame.Noise(message1))

        conn.setReadTimeout(MESSAGE_TIMEOUT_MS)
        val reply = conn.receiveHandshake() as? HandshakeFrame.Noise
            ?: transportError(TransportErrorCode.PROTOCOL_VIOLATION, "cần message Noise")
        val hostPayload = HandshakePayload.decode(state.readMessage(reply.message))
        val hostKey = hostKeyHint ?: state.remoteStaticKey
        if (hostPayload.role != DeviceRole.HOST || hostKey == null) transportError(TransportErrorCode.PROTOCOL_VIOLATION, "payload host sai")
        if (mode is ViewerAuthMode.Qr && !MessageDigest.isEqual(hostKey, mode.uri.hostPublicKey)) {
            transportError(TransportErrorCode.HOST_KEY_MISMATCH)
        }

        var method = PairMethod.RECONNECT
        if (pattern != NoisePattern.IK) {
            val payload = HandshakePayload(DeviceRole.VIEWER, deviceName, if (pattern == NoisePattern.XX) nonce else null)
            conn.sendHandshake(HandshakeFrame.Noise(state.writeMessage(payload.encode())))
            method = if (pattern == NoisePattern.XX) PairMethod.SAS_PAIRED else PairMethod.QR_PAIRED
        }
        conn.installSession(state.sessionKeys())
        if (mode is ViewerAuthMode.Sas) {
            val hash = state.messageTwoHash ?: transportError(TransportErrorCode.PROTOCOL_VIOLATION, "thiếu hash message 2")
            mode.onCode(ShortAuthString.format(ShortAuthString.code(hash, nonce)))
        }
        return InitiatorOutcome(hostKey, hostPayload.deviceName, method)
    }

    /** XX/XXpsk3: host trả `pair.result` sau khi người dùng quyết định. */
    private fun awaitPairingResult(conn: ControlConnection) {
        conn.setReadTimeout(PAIRING_DECISION_TIMEOUT_MS)
        val inbound = conn.nextInbound() ?: transportError(TransportErrorCode.CONNECTION_CLOSED)
        val message = (inbound as? ControlInbound.Message)?.envelope?.message
        when {
            message is ControlMessage.Reject -> {
                conn.close()
                throw TransportException(TransportErrorCode.REJECTED, message.detail, message.reason)
            }
            message is ControlMessage.PairResult && message.accepted -> Unit
            message is ControlMessage.PairResult -> {
                conn.close()
                transportError(TransportErrorCode.PAIRING_DENIED)
            }
            else -> {
                conn.close()
                transportError(TransportErrorCode.PROTOCOL_VIOLATION, "cần pair.result")
            }
        }
    }
}
