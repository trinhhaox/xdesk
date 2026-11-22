package vn.xox.xdesk.app

import android.content.ContentValues
import android.media.MediaFormat
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import java.io.File
import java.io.InputStream
import java.util.concurrent.Executors
import vn.xox.xdesk.app.discovery.DiscoveredHost
import vn.xox.xdesk.media.AndroidCodecList
import vn.xox.xdesk.media.VideoDecoder
import vn.xox.xdesk.transport.AgentApprovalRequest
import vn.xox.xdesk.transport.AgentHelpRequest
import vn.xox.xdesk.transport.ClipboardSendOutcome
import vn.xox.xdesk.transport.DisplayConfigPlanner
import vn.xox.xdesk.transport.FileTransferCompletion
import vn.xox.xdesk.transport.FileTransferNaming
import vn.xox.xdesk.transport.FileTransferProgress
import vn.xox.xdesk.transport.KnownHost
import vn.xox.xdesk.transport.SasPrompt
import vn.xox.xdesk.transport.TransportErrorCode
import vn.xox.xdesk.transport.ViewerAuth
import vn.xox.xdesk.transport.ViewerSession
import vn.xox.xdesk.transport.ViewerState
import vn.xox.xdesk.transport.ViewerTarget
import vn.xox.xdesk.transport.ViewerTrust
import vn.xox.xdesk.wire.ClipKind
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.DisplayInfo
import vn.xox.xdesk.wire.MediaKeyKind
import vn.xox.xdesk.wire.MirrorFit
import vn.xox.xdesk.wire.ScreenMode
import vn.xox.xdesk.wire.VideoCodec

/** Trạng thái UI + luồng kết nối. Việc mạng chạy trên một thread nền; trạng thái Compose chỉ ghi từ main thread. */
class ViewerController(
    internal val container: AppContainer,
    private val deviceName: String,
    private val screenSize: () -> Triple<Int, Int, Float>,
    private val maxRefreshRateHz: () -> Int = { 60 },
) : ViewModel() {
    private val main = Handler(Looper.getMainLooper())
    internal val background = Executors.newSingleThreadExecutor { Thread(it, "xdesk-connect") }
    internal val decoder = VideoDecoder({ session?.requestKeyframe() }, { post { onDecoderError(it) } }, onVideoSize = { w, h -> post { onVideoSize(w, h) } })
    private val audio = AppAudio()
    internal var session: ViewerSession? = null
        private set
    private var generation = 0 // tăng mỗi lần mở/đóng phiên: trạng thái muộn của phiên cũ bị bỏ qua
    private var surface: Surface? = null
    internal var lastTarget: ViewerTarget? = null
        private set
    private var lastIsPairing = false
    private var currentConfig: ControlMessage.DisplayConfig? = null
    internal val viewport = ViewportTracker(main)
    private var reconnectRunnable: Runnable? = null
    private var clipboardNoticeClear: Runnable? = null

    var screen by mutableStateOf(Screen.HOSTS)
    var hosts by mutableStateOf<List<DiscoveredHost>>(emptyList())
    var knownHosts by mutableStateOf<List<KnownHost>>(container.knownHosts.all())
    var connecting by mutableStateOf(false)
    var streaming by mutableStateOf(false)
    var reconnectAttempt by mutableStateOf(0)
        private set
    var clipboardAvailable by mutableStateOf(false)
        private set
    var audioAvailable by mutableStateOf(false)
        private set
    /** Mac chỉ bật khả năng truyền tệp khi thiết bị được cấp quyền "Gửi/nhận tệp"; thiếu thì ẩn nút gửi tệp. */
    val fileTransferAvailable: Boolean get() = streaming && session?.supportsFileTransfer == true
    var audioMuted by mutableStateOf(false)
        private set
    var hostDisplays by mutableStateOf<List<DisplayInfo>>(emptyList())
        private set
    var selectedDisplayId by mutableStateOf<Long?>(null)
        private set
    var activeFileTransfer by mutableStateOf<FileTransferProgress?>(null)
        private set
    var clipboardNotice by mutableStateOf<String?>(null)
        private set
    var sasPrompt by mutableStateOf<SasPrompt?>(null)
    var failure by mutableStateOf<ConnectionFailure?>(null)
    var pairTarget by mutableStateOf<ViewerTarget?>(null)
    var pairOnSas by mutableStateOf(false)
    /** Tiến trình kết nối cho lớp phủ "Đang kết nối" và phản hồi rung khi ghép đôi. */
    val progress = ConnectionProgress()
    var stats by mutableStateOf("")
    /** Yêu cầu duyệt agent AI đang chờ; null khi hết hạn, đã trả lời hoặc Mac đã duyệt trước. */
    var agentApproval by mutableStateOf<AgentApprovalRequest?>(null)
    /** Yêu cầu hỗ trợ agent AI đang chờ; null khi đã xong. */
    var agentHelp by mutableStateOf<AgentHelpRequest?>(null)
    /** Chế độ làm việc hiện tại của phiên (đổi ngay trong lúc kết nối). */
    var activeWorkMode by mutableStateOf(container.display.defaultWorkMode)
    /** Chế độ hiển thị đã thương lượng với Mac trong phiên hiện tại. */
    internal var negotiatedScreenMode: ScreenMode? = null
    val isControlMode: Boolean get() = activeWorkMode.isControlMode
    /** Cỡ khung video thật (px) để aspect-fit và đổi toạ độ chạm; null khi chưa biết (Giống màn hình Mac chờ decoder báo). */
    var videoSize by mutableStateOf<Pair<Int, Int>?>(null)
        private set
    var input: StreamInputRouter? = null
        private set

    /** Giống màn hình Mac: Mac giữ nguyên cỡ, viewer zoom/kéo; xoay máy không đàm phán lại. */
    val isNativeMirror: Boolean get() = currentConfig?.mirrorFit == MirrorFit.NATIVE

    val display: DisplaySettingsStore get() = container.display
    val deviceMaxRefreshHz: Int get() = maxRefreshRateHz()
    val trust: ViewerTrust? get() = container.trust()
    val identityError: String? get() = container.identityError
    val fingerprint: String? get() = container.identity?.fingerprint

    fun updateHosts(list: List<DiscoveredHost>) = post { hosts = list }

    fun connect(target: ViewerTarget) = start(listOf(target), ViewerAuth.Automatic)

    fun pairWithSas(target: ViewerTarget) {
        activeWorkMode = WorkMode.MIRROR
        start(listOf(target), ViewerAuth.Sas { prompt -> post { if (prompt.isPending) sasPrompt = prompt } }, isPairing = true)
    }

    internal fun start(targets: List<ViewerTarget>, auth: ViewerAuth, isPairing: Boolean = false) {
        val trust = trust ?: return run { failure = ConnectionFailure(identityError.orEmpty(), false) }
        val built = buildDisplayConfig() ?: return
        val (w, h, config) = built
        cancelPendingReconnect()
        lastIsPairing = isPairing
        negotiatedScreenMode = config.screenMode
        failure = null
        sasPrompt = null
        connecting = true
        progress.begin(isPairing)
        screen = Screen.STREAM
        lastTarget = targets.firstOrNull()
        progress.targetName = nameOf(lastTarget)
        viewport.requested = w to h
        currentConfig = config
        videoSize = if (config.mirrorFit == MirrorFit.NATIVE) null else config.w.toInt() to config.h.toInt()
        val hasHevc = config.codec == VideoCodec.HEVC
        val preferTcp = targets.isNotEmpty() && targets.all {
            it.host == "127.0.0.1" || it.host == "::1" || it.host.equals("localhost", ignoreCase = true)
        }
        val current = ++generation
        val next = ViewerSession(
            trust, deviceName, { decoder.submit(it) }, { post { if (current == generation) onState(it) } },
            { Thread(it, "xdesk-udp").also { t -> t.priority = Thread.MAX_PRIORITY } },
            onAgentApproval = { post { agentApproval = it } },
            onAgentHelp = { post { agentHelp = it } },
            audioSink = audio.sink,
            preferHevc = hasHevc,
            clipboardAccess = container.clipboard,
            preferMediaOverTcp = preferTcp,
            fileTempDir = File(container.appContext.cacheDir, "xdesk-transfers"),
            onDisplayList = { list -> post { if (current == generation) hostDisplays = list } },
            onFileProgress = { progress -> post { if (current == generation) activeFileTransfer = progress } },
            onFileReceived = { completion -> handleIncomingFile(completion) },
            onFileError = { name, err -> post { if (current == generation) showToast("Nhận tệp $name thất bại: $err") } },
            onUnlockResult = { result -> post { if (current == generation) showToast(result.message) } },
        )
        session = next
        input = StreamInputRouter(next).also { it.configure(config.w / config.scale.toFloat(), config.h / config.scale.toFloat()) }
        background.execute { next.connect(targets, config, auth) }
    }

    internal fun buildDisplayConfig(): Triple<Int, Int, ControlMessage.DisplayConfig>? {
        val (w, h, density) = viewport.actual?.let { Triple(it.first, it.second, screenSize().third) } ?: screenSize()
        val requestedCodec = if (container.display.videoCodec == VideoCodec.HEVC && container.display.supportsHevc) {
            VideoCodec.HEVC
        } else {
            VideoCodec.H264
        }
        val effectiveFps = container.display.qualityPreset.effectiveFps(maxRefreshRateHz()).toLong()
        val activeScreenMode = container.display.mode
        val config = DisplayConfigPlanner.config(
            w.toDouble(), h.toDouble(), density.toDouble(),
            fps = effectiveFps,
            codec = requestedCodec,
            mode = activeScreenMode, mirrorFit = container.display.fit,
        )?.copy(
            videoPaused = if (activeWorkMode.isControlMode) true else null,
            displayId = if (activeScreenMode == ScreenMode.MIRROR) selectedDisplayId else null,
        ) ?: return null
        return Triple(w, h, config)
    }

    internal fun applyReconfiguredConfig(w: Int, h: Int, config: ControlMessage.DisplayConfig) {
        negotiatedScreenMode = config.screenMode
        viewport.requested = w to h
        currentConfig = config
        videoSize = if (config.mirrorFit == MirrorFit.NATIVE) null else config.w.toInt() to config.h.toInt()
        input?.configure(config.w / config.scale.toFloat(), config.h / config.scale.toFloat())
        startDecoderIfReady()
    }

    private fun onState(state: ViewerState) {
        when (state) {
            ViewerState.Streaming -> {
                cancelPendingReconnect()
                reconnectAttempt = 0
                clipboardAvailable = session?.clipboardAvailable == true
                audioAvailable = session?.audioAvailable == true
                audio.player.muted = audioMuted
                connecting = false; streaming = true; sasPrompt = null; startDecoderIfReady(); checkViewport()
                progress.finish(true)
            }
            ViewerState.Connecting -> connecting = true
            ViewerState.Idle -> {
                connecting = false; streaming = false
                clipboardAvailable = false; audioAvailable = false
            }
            is ViewerState.Failed -> {
                if (screen == Screen.STREAM && sasPrompt == null && !lastIsPairing &&
                    state.code in TRANSIENT_RECONNECT_CODES && reconnectAttempt < RECONNECT_DELAYS_MS.size
                ) {
                    scheduleAutoReconnect()
                    return
                }
                cancelPendingReconnect()
                reconnectAttempt = 0
                clipboardAvailable = false
                audioAvailable = false
                audioMuted = false
                audio.player.muted = false
                hostDisplays = emptyList()
                selectedDisplayId = null
                activeFileTransfer = null
                connecting = false; streaming = false; sasPrompt = null; agentApproval = null
                activeWorkMode = container.display.defaultWorkMode
                negotiatedScreenMode = null
                decoder.stop()
                failure = ConnectionFailure(state.message, state.code in REPAIRABLE_CODES, state.code, progress.targetName)
                progress.finish(false)
                pairTarget = lastTarget
                screen = Screen.HOSTS
                knownHosts = container.knownHosts.all()
            }
        }
    }

    private fun scheduleAutoReconnect() {
        val primary = session?.connectedTarget ?: lastTarget ?: return
        val nextAttempt = reconnectAttempt + 1
        reconnectAttempt = nextAttempt
        connecting = true
        streaming = false
        decoder.stop()
        val delayMs = RECONNECT_DELAYS_MS[nextAttempt - 1]
        val task = Runnable {
            reconnectRunnable = null
            if (screen != Screen.STREAM) return@Runnable
            start(reconnectCandidates(primary), ViewerAuth.Automatic, isPairing = false)
        }
        reconnectRunnable = task
        main.postDelayed(task, delayMs)
    }

    private fun reconnectCandidates(primary: ViewerTarget): List<ViewerTarget> {
        val list = mutableListOf(primary)
        if (!TailscaleSupport.hasActiveInterface()) return list
        val matching = knownHosts.firstOrNull { it.id == primary.hostId }?.lastAddress
            ?: knownHosts.mapNotNull { it.lastAddress }.firstOrNull(TailscaleSupport::isTailscaleHost)
        val parsed = matching?.takeIf(TailscaleSupport::isTailscaleHost)?.let(ViewerTarget::parse)
            ?.copy(hostId = primary.hostId, name = primary.name)
        if (parsed != null && list.none { it.host == parsed.host && it.port == parsed.port }) {
            list.add(parsed)
        }
        return list
    }

    private fun cancelPendingReconnect() {
        reconnectRunnable?.let(main::removeCallbacks)
        reconnectRunnable = null
    }

    fun attachSurface(newSurface: Surface) { surface = newSurface; startDecoderIfReady() }

    fun detachSurface() { surface = null; decoder.stop() }

    /** Lỗi decoder chỉ đáng báo khi phiên còn sống; sau khi người dùng ngắt hoặc đang mở lại phiên thì bỏ qua. */
    private fun onDecoderError(message: String) { if (session != null && streaming) failure = ConnectionFailure(message, false) }

    private fun startDecoderIfReady() {
        val target = surface ?: return
        val config = currentConfig ?: return
        if (!streaming) return
        decoder.recorder = container.streamRecorder()
        // Giống màn hình Mac: cỡ thật do host quyết (tới 2560 cạnh dài) nên báo trần để decoder khỏi cấu hình lại.
        val maxSize = if (isNativeMirror) mapOf(MediaFormat.KEY_MAX_WIDTH to NATIVE_MAX_EDGE, MediaFormat.KEY_MAX_HEIGHT to NATIVE_MAX_EDGE) else emptyMap()
        val mime = if (config.codec == VideoCodec.HEVC) AndroidCodecList.MIME_HEVC else AndroidCodecList.MIME_AVC
        if (decoder.start(target, config.w.toInt(), config.h.toInt(), maxSize, mime = mime)) {
            session?.requestKeyframe()
        }
    }

    private fun onVideoSize(w: Int, h: Int) {
        videoSize = w to h
        progress.frameShown = true
        if (isNativeMirror) input?.configure(w / MAC_POINT_RATIO, h / MAC_POINT_RATIO)
    }

    fun disconnect() {
        cancelPendingReconnect()
        reconnectAttempt = 0
        clipboardAvailable = false
        audioAvailable = false
        audioMuted = false
        audio.player.muted = false
        hostDisplays = emptyList()
        selectedDisplayId = null
        activeFileTransfer = null
        clearClipboardNotice()
        // Huỷ lúc đang so mã: trả lời "không khớp" để đóng kết nối và nhả luồng đang chờ ngay.
        sasPrompt?.answer(false)
        sasPrompt = null
        activeWorkMode = container.display.defaultWorkMode
        negotiatedScreenMode = null
        val ending = session
        if (ending == null) {
            connecting = false; streaming = false; agentApproval = null; agentHelp = null
            screen = Screen.HOSTS
            knownHosts = container.knownHosts.all()
            return
        }
        endSession()
        session = null
        input = null
        decoder.stop()
        background.execute { ending.disconnect() }
        connecting = false; streaming = false; agentApproval = null; agentHelp = null
        screen = Screen.HOSTS
        knownHosts = container.knownHosts.all()
    }

    fun answerAgentApproval(allow: Boolean) { session?.answerAgentApproval(allow); agentApproval = null }

    fun resolveAgentHelp(requestId: String) { session?.resolveAgentHelp(requestId); agentHelp = null }

    fun sendSystemLock() { session?.sendSystemLock() }

    fun sendSystemUnlock() { session?.sendSystemUnlock() }

    fun sendText(text: String) { session?.sendText(text) }

    fun sendInput(events: List<vn.xox.xdesk.wire.InputEvent>) { session?.sendInput(events) }

    fun sendFile(name: String, bytes: ByteArray) { session?.sendFile(name, bytes) }

    fun sendFileStream(name: String, totalBytes: Long, openStream: () -> InputStream?) {
        val activeSession = session ?: return showToast("Chưa kết nối tới Mac")
        activeSession.sendFile(name, totalBytes, openStream) { ok, err ->
            post {
                when {
                    ok -> showToast("Đã gửi tệp $name sang Mac")
                    err == "cancelled" -> showToast("Đã huỷ gửi tệp")
                    else -> showToast("Gửi tệp thất bại: ${err ?: "Lỗi không rõ"}")
                }
            }
        }
    }

    fun cancelFileTransfer() { session?.cancelFileTransfer() }

    fun toggleAudioMute() {
        audioMuted = !audioMuted
        audio.player.muted = audioMuted
        showToast(if (audioMuted) "Đã tắt tiếng trên thiết bị" else "Đã bật tiếng")
    }

    fun selectHostDisplay(displayId: Long) {
        if (selectedDisplayId == displayId) return
        val target = session?.connectedTarget ?: lastTarget ?: return
        selectedDisplayId = displayId
        reconfigureOrRestart(target)
    }

    fun sendMediaKey(key: MediaKeyKind) { session?.sendMediaKey(key) }

    fun showToast(message: String) = showClipboardNotice(message)

    private fun handleIncomingFile(completion: FileTransferCompletion) {
        try {
            val savedName = saveFileToDownloads(completion.file, completion.fileName)
            completion.file.delete()
            post { showToast("Đã lưu $savedName vào Downloads/Xdesk") }
        } catch (e: Exception) {
            completion.file.delete()
            post { showToast("Lưu tệp ${completion.fileName} thất bại: ${e.message}") }
        }
    }

    private fun saveFileToDownloads(source: File, preferredName: String): String {
        val resolver = container.appContext.contentResolver
        val relative = "${Environment.DIRECTORY_DOWNLOADS}/Xdesk"
        val cleanName = FileTransferNaming.sanitizedName(preferredName)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, cleanName)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Không tạo được mục Downloads")
        resolver.openOutputStream(uri)?.use { out ->
            source.inputStream().use { input -> input.copyTo(out) }
        } ?: throw IllegalStateException("Không ghi được vào Downloads")
        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return cleanName
    }

    /** Đọc clipboard Android và gửi sang Mac khi người dùng bấm "Gửi clipboard sang Mac". */
    fun sendClipboardToMac() {
        val activeSession = session ?: return showClipboardNotice("Mac chưa cho phép clipboard cho thiết bị này")
        activeSession.sendClipboard { outcome ->
            val notice = when (outcome) {
                is ClipboardSendOutcome.Sent -> if (outcome.kind == ClipKind.TEXT) {
                    "Đã gửi văn bản sang Mac"
                } else {
                    "Đã gửi ảnh sang Mac"
                }
                ClipboardSendOutcome.Disabled -> "Mac chưa cho phép clipboard cho thiết bị này"
                ClipboardSendOutcome.NothingToSend -> "Clipboard trống, quá 10 MB hoặc là mật khẩu (không gửi)"
                is ClipboardSendOutcome.Failed -> "Không gửi được: ${outcome.reason}"
            }
            post { showClipboardNotice(notice) }
        }
    }

    private fun showClipboardNotice(message: String) {
        clipboardNoticeClear?.let(main::removeCallbacks)
        clipboardNotice = message
        val task = Runnable { clipboardNotice = null; clipboardNoticeClear = null }
        clipboardNoticeClear = task
        main.postDelayed(task, 3000L)
    }

    private fun clearClipboardNotice() {
        clipboardNoticeClear?.let(main::removeCallbacks)
        clipboardNoticeClear = null
        clipboardNotice = null
    }

    fun refreshStats() {
        val s = session ?: return
        val sound = audio.player.stats.takeIf { it.packets > 0 }?.let { " · tiếng ${it.codec} ${it.estimatedLatencyMs(s.rttMs ?: 0)} ms" }.orEmpty()
        stats = "${decoder.codecName ?: "-"} · ${s.fps} fps · ${s.recvKbps} kbps · RTT ${s.rttMs ?: "-"} ms$sound"
    }

    fun resetIdentity() { container.resetIdentity(); knownHosts = container.knownHosts.all() }

    internal fun checkViewport() {
        val target = session?.connectedTarget ?: lastTarget ?: return
        viewport.schedule(streaming, isNativeMirror) { reconfigureOrRestart(target) }
    }

    /** Vô hiệu mọi việc đang chờ của phiên hiện tại (trạng thái muộn, hẹn mở lại theo viewport) trước khi đóng/mở lại. */
    internal fun endSession() {
        cancelPendingReconnect()
        generation++
        viewport.cancel()
        streaming = false
        clipboardAvailable = false
        audioAvailable = false
        activeFileTransfer = null
    }

    internal fun post(block: () -> Unit) { main.post(block) }

    override fun onCleared() {
        cancelPendingReconnect()
        endSession()
        session?.disconnect()
        decoder.release()
        background.shutdownNow()
    }

    private companion object {
        const val NATIVE_MAX_EDGE = 2560
        /** Mac Retina: 2 px video mỗi điểm; chỉ dùng để quy ngưỡng/delta cuộn ra điểm host. */
        const val MAC_POINT_RATIO = 2f
        val RECONNECT_DELAYS_MS = longArrayOf(1000L, 2000L, 4000L)
        val TRANSIENT_RECONNECT_CODES = setOf(
            TransportErrorCode.LINK_LOST,
            TransportErrorCode.CONNECTION_FAILED,
            TransportErrorCode.TIMED_OUT,
            TransportErrorCode.CONNECTION_CLOSED,
        )
    }
}
