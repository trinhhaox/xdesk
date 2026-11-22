package vn.xox.xdesk.transport

import vn.xox.xdesk.wire.Capabilities
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.UnlockAttestation

/** Người dùng huỷ bước xác thực sinh trắc học khi ký thử thách mở khoá. */
class UnlockCancelledException : Exception("Đã huỷ xác thực mở khoá Mac")

/** Khoá mở khoá đã bị vô hiệu (đổi sinh trắc học/khoá màn hình): khoá cũ đã xoá và tạo khoá mới, cần đăng ký lại trên Mac. */
class UnlockKeyInvalidatedException : Exception("Khoá mở khoá đã bị vô hiệu")

/**
 * Khoá ký gắn với xác thực sinh trắc học của điện thoại (Android: AndroidKeyStore + BiometricPrompt CryptoObject).
 * Giao diện bất đồng bộ vì việc ký chờ người dùng chạm vân tay/nhập mã.
 */
interface UnlockSigner {
    /** Khoá công khai X9.63 (65 byte); tạo khoá nếu chưa có (không cần xác thực người dùng). */
    fun publicKey(): ByteArray

    /** Khoá công khai đã có (không tạo mới) hoặc `null`; dùng để hiện dấu vân tay trong Cài đặt. */
    fun existingPublicKey(): ByteArray?

    /**
     * Ký ECDSA-SHA256 (DER) lên [message]; việc ký kích hoạt xác thực, lời nhắc nêu tên [hostName].
     * [onResult] chạy trên thread bất kỳ, đúng một lần.
     */
    fun sign(message: ByteArray, hostName: String, onResult: (Result<ByteArray>) -> Unit)
}

/** Khoá tĩnh Noise và tên của host đang kết nối (gắn vào dữ liệu ký và lời nhắc xác thực). */
class UnlockHostInfo(val key: ByteArray, val name: String)

/**
 * Phía viewer của mở khoá có chứng thực: đăng ký khoá công khai và trả lời thử thách của host.
 * Chỉ ký khi người dùng vừa bấm "Mở khoá Mac" ([arm], hiệu lực 30 s và đúng một thử thách); thử thách không mời bị bỏ.
 */
internal class UnlockAttestationClient(
    private val signer: UnlockSigner?,
    private val viewerKey: ByteArray,
    private val host: () -> UnlockHostInfo?,
    private val nowMs: () -> Long,
    private val send: (ControlMessage) -> Unit,
    private val onResult: (ControlMessage.SystemUnlockResult) -> Unit,
) {
    @Volatile private var armedUntilMs = 0L
    @Volatile private var negotiated = 0L
    val offered: Boolean get() = signer != null

    fun registerKey(negotiatedCaps: Long) {
        negotiated = negotiatedCaps
        val signer = signer ?: return
        if (negotiatedCaps and Capabilities.UNLOCK_ATTESTATION == 0L) return
        val pub = try { signer.publicKey() } catch (e: Exception) { return }
        send(ControlMessage.UnlockKey(UnlockAttestation.ALGORITHM, UnlockAttestation.encode(pub)))
    }

    fun arm() { armedUntilMs = nowMs() + WINDOW_MS }

    fun reset() { armedUntilMs = 0L }

    private fun consumeArm(): Boolean {
        val until = armedUntilMs
        armedUntilMs = 0L
        return until != 0L && nowMs() <= until
    }

    fun answer(challenge: ControlMessage.SystemUnlockChallenge) {
        val signer = signer ?: return
        if (!consumeArm()) return
        val nonce = UnlockAttestation.decodeNonce(challenge.nonce) ?: return
        val info = host() ?: return
        signer.sign(UnlockAttestation.signedMessage(info.key, viewerKey, nonce), info.name) { result ->
            result.fold(
                onSuccess = { send(ControlMessage.SystemUnlock(sig = UnlockAttestation.encode(it))) },
                onFailure = { handleFailure(it) },
            )
        }
    }

    private fun handleFailure(error: Throwable) {
        when (error) {
            is UnlockCancelledException -> onResult(ControlMessage.SystemUnlockResult(false, error.message.orEmpty()))
            is UnlockKeyInvalidatedException -> {
                registerKey(negotiated)
                onResult(ControlMessage.SystemUnlockResult(false, INVALIDATED_MESSAGE))
            }
            else -> onResult(ControlMessage.SystemUnlockResult(false, "Không xác thực được để mở khoá Mac"))
        }
    }

    companion object {
        const val WINDOW_MS = 30_000L
        const val INVALIDATED_MESSAGE = "Khoá Face ID/vân tay đã bị vô hiệu. Trên Mac, bấm \"Đặt lại khoá\" rồi mở khoá lại từ điện thoại"
    }
}
