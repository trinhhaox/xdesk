package vn.xox.xdesk.wire

enum class VideoCodec(val wire: String) { H264("h264"), HEVC("hevc") }
enum class ScreenMode(val wire: String) { EXTEND("extend"), MIRROR("mirror") }
/** Chỉ có nghĩa khi mode = MIRROR; xem protocol/spec/control-messages.md. */
enum class MirrorFit(val wire: String) { NATIVE("native"), FIT_DEVICE("fitDevice"), TOUCH("touch") }
enum class ClipKind(val wire: String) { TEXT("text"), IMAGE("image") }
enum class ControlOwner(val wire: String) { AGENT("agent"), HUMAN("human") }
enum class MediaKeyKind(val wire: String) {
    PLAY_PAUSE("playPause"),
    NEXT("next"),
    PREVIOUS("previous"),
    VOLUME_UP("volumeUp"),
    VOLUME_DOWN("volumeDown"),
    MUTE("mute"),
}

enum class WindowAdjustOp(val wire: String) { MOVE("move"), RESIZE("resize"), PRESET("preset") }
enum class WindowPreset(val wire: String) {
    FILL("fill"), LEFT("left"), RIGHT("right"), CENTER("center"), RESTORE("restore"),
}

/** Khung cửa sổ theo toạ độ điểm của luồng video viewer. */
data class WindowFrame(val x: Double, val y: Double, val w: Double, val h: Double) {
    internal val isValid: Boolean get() = x.isFinite() && y.isFinite() && w.isFinite() && h.isFinite() && w > 0.0 && h > 0.0
}

data class DisplayInfo(
    val id: Long,
    val name: String,
    val width: Long,
    val height: Long,
    val isMain: Boolean,
)

/** Giới hạn truyền tệp streaming qua frame `BULK` (tối đa 2 GiB, mỗi chunk ≤ 64 KiB). */
object FileTransferLimits {
    const val MAX_BYTES = 2_147_483_648L
    const val MAX_ID_BYTES = 64
    const val MAX_NAME_BYTES = 255
    const val CHUNK_BYTES = 65_536
}

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
    /** `mode` vắng = extend; `mirrorFit` vắng = fitDevice; `displayId` vắng = màn hình mặc định. */
    data class DisplayConfig(
        val w: Long, val h: Long, val scale: Double, val fps: Long, val codec: VideoCodec, val mode: ScreenMode? = null,
        val mirrorFit: MirrorFit? = null, val videoPaused: Boolean? = null, val displayId: Long? = null,
    ) : ControlMessage {
        val screenMode: ScreenMode get() = mode ?: ScreenMode.EXTEND
        val fit: MirrorFit get() = mirrorFit ?: MirrorFit.FIT_DEVICE
    }
    data class DisplayReconfigure(val config: DisplayConfig) : ControlMessage
    data class DisplayReady(val udpPort: Int, val streamId: Int) : ControlMessage
    data class KeyframeRequest(val streamId: Int) : ControlMessage
    data class VideoPause(val streamId: Int) : ControlMessage
    data class VideoResume(val streamId: Int) : ControlMessage
    data class NetReport(val rttMs: Long, val lossPermille: Long, val jitterMs: Long, val recvKbps: Long) : ControlMessage
    data class BitrateSet(val kbps: Long) : ControlMessage
    data class ClipOffer(val kind: ClipKind, val size: Long, val hash: String? = null) : ControlMessage
    data class ClipPull(val kind: ClipKind) : ControlMessage
    data class ClipData(val kind: ClipKind, val size: Long, val hash: String) : ControlMessage
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
    /** Host → viewer: kết quả khoá màn hình Mac (không cần cap; viewer cũ bỏ qua type lạ). */
    data class SystemLockResult(val ok: Boolean, val message: String) : ControlMessage
    /** Host → viewer: Mac khoá/tắt màn hình nên chưa có hình ([videoAvailable]=false); control/input/unlock vẫn dùng được. */
    data class HostState(val videoAvailable: Boolean, val locked: Boolean) : ControlMessage
    /** Không có `sig` → xin thử thách; có `sig` (base64 DER ECDSA) → trả lời thử thách. */
    data class SystemUnlock(val token: String? = null, val sig: String? = null) : ControlMessage
    data class SystemUnlockResult(val ok: Boolean, val message: String) : ControlMessage
    /** Host → viewer: nonce base64 32 byte, dùng một lần, hết hạn sau [ttlMs]. */
    data class SystemUnlockChallenge(val nonce: String, val ttlMs: Long) : ControlMessage
    /** Viewer → host: khoá công khai (X9.63, base64) của khoá sinh trắc học. */
    data class UnlockKey(val alg: String, val pub: String) : ControlMessage
    data class MediaKey(val key: MediaKeyKind) : ControlMessage
    data class DisplayList(val displays: List<DisplayInfo>) : ControlMessage
    data class FileOffer(val name: String, val size: Long, val hash: String) : ControlMessage
    data class FileData(val name: String, val chunk: String, val isLast: Boolean) : ControlMessage
    data class FileStart(val id: String, val name: String, val size: Long) : ControlMessage
    data class FileChunk(val id: String, val size: Long) : ControlMessage
    data class FileDone(val id: String, val hash: String) : ControlMessage
    data class FileCancel(val id: String, val reason: String? = null) : ControlMessage
    data class AgentHelp(val requestId: String, val reason: String? = null, val resolved: Boolean? = null) : ControlMessage {
        val isRequest: Boolean get() = resolved != true
        val isResolved: Boolean get() = resolved == true
        companion object {
            fun request(requestId: String, reason: String) = AgentHelp(requestId, reason = reason)
            fun resolved(requestId: String) = AgentHelp(requestId, resolved = true)
            fun resolve(requestId: String) = resolved(requestId)
        }
    }
    /** Viewer → host (cap `windowControl`): chọn cửa sổ trên cùng tại điểm (x, y). */
    data class WindowPick(val x: Double, val y: Double) : ControlMessage
    /** Host → viewer: kết quả chọn/chỉnh; `ok == false` kèm [message] tiếng Việt. */
    data class WindowSelected(
        val ok: Boolean,
        val windowId: Long? = null,
        val app: String? = null,
        val title: String? = null,
        val frame: WindowFrame? = null,
        val resizable: Boolean? = null,
        val message: String? = null,
    ) : ControlMessage {
        companion object {
            const val MAX_TEXT_BYTES = 256
            fun failure(message: String) = WindowSelected(ok = false, message = message)
        }
    }
    /** `move` cần dx,dy; `resize` cần w,h (> 0); `preset` cần [preset]. */
    data class WindowAdjust(
        val windowId: Long,
        val op: WindowAdjustOp,
        val dx: Double? = null,
        val dy: Double? = null,
        val w: Double? = null,
        val h: Double? = null,
        val preset: WindowPreset? = null,
    ) : ControlMessage {
        companion object {
            fun move(windowId: Long, dx: Double, dy: Double) = WindowAdjust(windowId, WindowAdjustOp.MOVE, dx = dx, dy = dy)
            fun resize(windowId: Long, w: Double, h: Double) = WindowAdjust(windowId, WindowAdjustOp.RESIZE, w = w, h = h)
            fun preset(windowId: Long, preset: WindowPreset) = WindowAdjust(windowId, WindowAdjustOp.PRESET, preset = preset)
        }
    }
    data class Unknown(val type: String) : ControlMessage
}

/** Message kèm `id` (u32) để ghép yêu cầu/phản hồi. */
data class ControlEnvelope(val id: Long, val message: ControlMessage)

/** Giới hạn clipboard: văn bản (UTF-8) và ảnh PNG đều ≤ 10 MiB. */
object ClipLimits {
    const val MAX_BYTES = 10 * 1024 * 1024

    fun isValidHash(text: String): Boolean =
        text.length == 64 && text.all { it in '0'..'9' || it in 'a'..'f' }
}

internal fun ControlMessage.validate() {
    when (this) {
        is ControlMessage.DisplayConfig -> validateDisplayConfig(this)
        is ControlMessage.DisplayReconfigure -> validateDisplayConfig(config)
        is ControlMessage.DisplayReady ->
            if (udpPort == 0) wireError(WireErrorCode.invalidField, "display.ready.udpPort")
        is ControlMessage.InputText ->
            if (text.toByteArray(Charsets.UTF_8).size > ControlMessage.InputText.MAX_BYTES) {
                wireError(WireErrorCode.invalidField, "input.text.text")
            }
        is ControlMessage.NetReport ->
            if (lossPermille > 1000) wireError(WireErrorCode.invalidField, "net.report.lossPermille")
        is ControlMessage.AgentApprove -> validateAgentApprove()
        is ControlMessage.SystemUnlock, is ControlMessage.SystemUnlockChallenge, is ControlMessage.UnlockKey -> validateUnlockAttestation()
        is ControlMessage.ClipOffer -> {
            if (size < 1L || size > ClipLimits.MAX_BYTES) wireError(WireErrorCode.invalidField, "clip.offer.size")
            if (hash != null && !ClipLimits.isValidHash(hash)) wireError(WireErrorCode.invalidField, "clip.offer.hash")
        }
        is ControlMessage.ClipData -> {
            if (size < 1L || size > ClipLimits.MAX_BYTES) wireError(WireErrorCode.invalidField, "clip.data.size")
            if (!ClipLimits.isValidHash(hash)) wireError(WireErrorCode.invalidField, "clip.data.hash")
        }
        is ControlMessage.FileStart -> {
            val idBytes = id.toByteArray(Charsets.UTF_8).size
            val nameBytes = name.toByteArray(Charsets.UTF_8).size
            if (id.isEmpty() || idBytes > FileTransferLimits.MAX_ID_BYTES) wireError(WireErrorCode.invalidField, "file.start.id")
            if (name.isEmpty() || nameBytes > FileTransferLimits.MAX_NAME_BYTES) wireError(WireErrorCode.invalidField, "file.start.name")
            if (size < 0L || size > FileTransferLimits.MAX_BYTES) wireError(WireErrorCode.invalidField, "file.start.size")
        }
        is ControlMessage.FileChunk -> {
            val idBytes = id.toByteArray(Charsets.UTF_8).size
            if (id.isEmpty() || idBytes > FileTransferLimits.MAX_ID_BYTES) wireError(WireErrorCode.invalidField, "file.chunk.id")
            if (size < 1L || size > FileTransferLimits.CHUNK_BYTES) wireError(WireErrorCode.invalidField, "file.chunk.size")
        }
        is ControlMessage.FileDone -> {
            val idBytes = id.toByteArray(Charsets.UTF_8).size
            if (id.isEmpty() || idBytes > FileTransferLimits.MAX_ID_BYTES) wireError(WireErrorCode.invalidField, "file.done.id")
            if (!ClipLimits.isValidHash(hash)) wireError(WireErrorCode.invalidField, "file.done.hash")
        }
        is ControlMessage.FileCancel -> {
            val idBytes = id.toByteArray(Charsets.UTF_8).size
            if (id.isEmpty() || idBytes > FileTransferLimits.MAX_ID_BYTES) wireError(WireErrorCode.invalidField, "file.cancel.id")
        }
        is ControlMessage.WindowPick, is ControlMessage.WindowSelected, is ControlMessage.WindowAdjust -> ControlWindowFields.validate(this)
        else -> Unit
    }
}

private fun validateDisplayConfig(config: ControlMessage.DisplayConfig) {
    if (config.w !in 1..16384 || config.h !in 1..16384) wireError(WireErrorCode.invalidField, "display.config.size")
    if (config.fps !in 1..240) wireError(WireErrorCode.invalidField, "display.config.fps")
    if (!config.scale.isFinite() || config.scale <= 0.0 || config.scale > 8.0) wireError(WireErrorCode.invalidField, "display.config.scale")
}

private fun ControlMessage.AgentApprove.validateAgentApprove() {
    fun bytes(s: String?) = s?.toByteArray(Charsets.UTF_8)?.size ?: 0
    if (requestId.isEmpty() || bytes(requestId) > ControlMessage.AgentApprove.MAX_ID_BYTES) wireError(WireErrorCode.invalidField, "agent.approve.requestId")
    if (bytes(agentName) > ControlMessage.AgentApprove.MAX_NAME_BYTES) wireError(WireErrorCode.invalidField, "agent.approve.agentName")
    if (bytes(summary) > ControlMessage.AgentApprove.MAX_SUMMARY_BYTES) wireError(WireErrorCode.invalidField, "agent.approve.summary")
}
