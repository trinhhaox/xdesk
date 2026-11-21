package vn.xox.xdesk.wire

enum class VideoCodec(val wire: String) { H264("h264"), HEVC("hevc") }
enum class ScreenMode(val wire: String) { EXTEND("extend"), MIRROR("mirror") }
/** Chỉ có nghĩa khi mode = MIRROR; xem protocol/spec/control-messages.md. */
enum class MirrorFit(val wire: String) { NATIVE("native"), FIT_DEVICE("fitDevice"), TOUCH("touch") }
enum class ClipKind(val wire: String) { TEXT("text"), IMAGE("image") }
enum class ControlOwner(val wire: String) { AGENT("agent"), HUMAN("human") }

/** Message điều khiển có kiểu; `t` lạ → [Unknown] (tương thích tiến). u32 là `Long`, u16 là `Int`. */
sealed interface ControlMessage {
    data class Hello(val ver: String, val caps: Long, val name: String) : ControlMessage
    data class Welcome(val ver: String, val sessionId: String, val caps: Long) : ControlMessage
    data class Reject(val reason: String, val detail: String? = null) : ControlMessage {
        companion object {
            const val REASON_VERSION = "version"
            const val REASON_REVOKED = "revoked"
        }
    }
    /** `mode` vắng = extend; `mirrorFit` vắng = fitDevice. */
    data class DisplayConfig(
        val w: Long, val h: Long, val scale: Double, val fps: Long, val codec: VideoCodec, val mode: ScreenMode? = null,
        val mirrorFit: MirrorFit? = null,
    ) : ControlMessage {
        val screenMode: ScreenMode get() = mode ?: ScreenMode.EXTEND
        val fit: MirrorFit get() = mirrorFit ?: MirrorFit.FIT_DEVICE
    }
    data class DisplayReady(val udpPort: Int, val streamId: Int) : ControlMessage
    data class KeyframeRequest(val streamId: Int) : ControlMessage
    data class NetReport(val rttMs: Long, val lossPermille: Long, val jitterMs: Long, val recvKbps: Long) : ControlMessage
    data class BitrateSet(val kbps: Long) : ControlMessage
    data class ClipOffer(val kind: ClipKind, val size: Long) : ControlMessage
    data class ClipPull(val kind: ClipKind) : ControlMessage
    data class ControlState(val owner: ControlOwner) : ControlMessage
    data class Ping(val t0: Long) : ControlMessage
    data class Pong(val t0: Long, val t1: Long, val t2: Long) : ControlMessage
    data class Bye(val reason: String? = null) : ControlMessage
    data class InputText(val text: String) : ControlMessage {
        companion object { const val MAX_BYTES = 4096 }
    }
    data object Rekey : ControlMessage
    data class RekeyResync(val epoch: Long, val ask: Boolean) : ControlMessage
    data class PairResult(val accepted: Boolean) : ControlMessage
    /**
     * Xin duyệt quyền điều khiển cho agent AI, hai chiều trên cùng type. Yêu cầu (host→viewer): `agentName`, `summary`,
     * `expiresAt` (ms Unix, giờ host), không có `allow`. Trả lời (viewer→host): chỉ `requestId` + `allow`.
     */
    data class AgentApprove(
        val requestId: String,
        val agentName: String? = null,
        val summary: String? = null,
        val expiresAt: Long? = null,
        val allow: Boolean? = null,
    ) : ControlMessage {
        /** `allow` vắng = đây là yêu cầu duyệt. */
        val isRequest: Boolean get() = allow == null

        companion object {
            const val MAX_ID_BYTES = 64
            const val MAX_NAME_BYTES = 128
            const val MAX_SUMMARY_BYTES = 512

            fun response(requestId: String, allow: Boolean) = AgentApprove(requestId, allow = allow)
        }
    }
    data object SystemLock : ControlMessage
    data class SystemUnlock(val token: String? = null) : ControlMessage
    data class FileOffer(val name: String, val size: Long, val hash: String) : ControlMessage
    data class FileData(val name: String, val chunk: String, val isLast: Boolean) : ControlMessage
    data class AgentHelp(val requestId: String, val reason: String? = null, val resolved: Boolean? = null) : ControlMessage {
        val isRequest: Boolean get() = resolved != true
        val isResolved: Boolean get() = resolved == true
        companion object {
            fun request(requestId: String, reason: String) = AgentHelp(requestId, reason = reason)
            fun resolved(requestId: String) = AgentHelp(requestId, resolved = true)
            fun resolve(requestId: String) = resolved(requestId)
        }
    }
    data class Unknown(val type: String) : ControlMessage
}

/** Message kèm `id` (u32) để ghép yêu cầu/phản hồi. */
data class ControlEnvelope(val id: Long, val message: ControlMessage)

internal fun ControlMessage.validate() {
    when (this) {
        is ControlMessage.DisplayConfig -> {
            if (w !in 1..16384 || h !in 1..16384) wireError(WireErrorCode.invalidField, "display.config.size")
            if (fps !in 1..240) wireError(WireErrorCode.invalidField, "display.config.fps")
            if (!scale.isFinite() || scale <= 0.0 || scale > 8.0) wireError(WireErrorCode.invalidField, "display.config.scale")
        }
        is ControlMessage.DisplayReady ->
            if (udpPort == 0) wireError(WireErrorCode.invalidField, "display.ready.udpPort")
        is ControlMessage.InputText ->
            if (text.toByteArray(Charsets.UTF_8).size > ControlMessage.InputText.MAX_BYTES) {
                wireError(WireErrorCode.invalidField, "input.text.text")
            }
        is ControlMessage.NetReport ->
            if (lossPermille > 1000) wireError(WireErrorCode.invalidField, "net.report.lossPermille")
        is ControlMessage.AgentApprove -> validateAgentApprove()
        else -> Unit
    }
}

private fun ControlMessage.AgentApprove.validateAgentApprove() {
    fun bytes(s: String?) = s?.toByteArray(Charsets.UTF_8)?.size ?: 0
    if (requestId.isEmpty() || bytes(requestId) > ControlMessage.AgentApprove.MAX_ID_BYTES) wireError(WireErrorCode.invalidField, "agent.approve.requestId")
    if (bytes(agentName) > ControlMessage.AgentApprove.MAX_NAME_BYTES) wireError(WireErrorCode.invalidField, "agent.approve.agentName")
    if (bytes(summary) > ControlMessage.AgentApprove.MAX_SUMMARY_BYTES) wireError(WireErrorCode.invalidField, "agent.approve.summary")
}
