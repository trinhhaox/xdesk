package vn.xox.xdesk.app

import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import java.util.concurrent.Executors
import vn.xox.xdesk.app.discovery.DiscoveredHost
import vn.xox.xdesk.media.VideoDecoder
import vn.xox.xdesk.transport.AgentApprovalRequest
import vn.xox.xdesk.transport.DisplayConfigPlanner
import vn.xox.xdesk.transport.KnownHost
import vn.xox.xdesk.transport.TransportErrorCode
import vn.xox.xdesk.transport.ViewerAuth
import vn.xox.xdesk.transport.ViewerSession
import vn.xox.xdesk.transport.ViewerState
import vn.xox.xdesk.transport.ViewerTarget
import vn.xox.xdesk.transport.ViewerTrust
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.MirrorFit

/** Trạng thái UI + luồng kết nối. Việc mạng chạy trên một thread nền; trạng thái Compose chỉ ghi từ main thread. */
class ViewerController(private val container: AppContainer, private val deviceName: String, private val screenSize: () -> Triple<Int, Int, Float>) : ViewModel() {
    private val main = Handler(Looper.getMainLooper())
    private val background = Executors.newSingleThreadExecutor { Thread(it, "xdesk-connect") }
    private val decoder = VideoDecoder({ session?.requestKeyframe() }, { post { onDecoderError(it) } }, onVideoSize = { w, h -> post { onVideoSize(w, h) } })
    private val audio = AppAudio()
    private var session: ViewerSession? = null
    private var generation = 0 // tăng mỗi lần mở/đóng phiên: trạng thái muộn của phiên cũ bị bỏ qua
    private var surface: Surface? = null
    private var lastTarget: ViewerTarget? = null
    private var currentConfig: ControlMessage.DisplayConfig? = null
    private val viewport = ViewportTracker(main)

    var screen by mutableStateOf(Screen.HOSTS)
    var hosts by mutableStateOf<List<DiscoveredHost>>(emptyList())
    var knownHosts by mutableStateOf<List<KnownHost>>(container.knownHosts.all())
    var connecting by mutableStateOf(false)
    var streaming by mutableStateOf(false)
    var sasCode by mutableStateOf<String?>(null)
    var failure by mutableStateOf<ConnectionFailure?>(null)
    var pairTarget by mutableStateOf<ViewerTarget?>(null)
    var stats by mutableStateOf("")
    /** Yêu cầu duyệt agent AI đang chờ; null khi hết hạn, đã trả lời hoặc Mac đã duyệt trước. */
    var agentApproval by mutableStateOf<AgentApprovalRequest?>(null)
    /** Cỡ khung video thật (px) để aspect-fit và đổi toạ độ chạm; null khi chưa biết (Giống màn hình Mac chờ decoder báo). */
    var videoSize by mutableStateOf<Pair<Int, Int>?>(null)
        private set
    var input: StreamInputRouter? = null
        private set

    /** Giống màn hình Mac: Mac giữ nguyên cỡ, viewer zoom/kéo; xoay máy không đàm phán lại. */
    val isNativeMirror: Boolean get() = currentConfig?.mirrorFit == MirrorFit.NATIVE

    val display: DisplaySettingsStore get() = container.display
    val trust: ViewerTrust? get() = container.trust()
    val identityError: String? get() = container.identityError
    val fingerprint: String? get() = container.identity?.fingerprint

    fun updateHosts(list: List<DiscoveredHost>) = post { hosts = list }

    fun connect(target: ViewerTarget) = start(listOf(target), ViewerAuth.Automatic)

    fun pairWithSas(target: ViewerTarget) = start(listOf(target), ViewerAuth.Sas { code -> post { sasCode = code } })

    internal fun start(targets: List<ViewerTarget>, auth: ViewerAuth) {
        val trust = trust ?: return run { failure = ConnectionFailure(identityError.orEmpty(), false) }
        val (w, h, density) = viewport.actual?.let { Triple(it.first, it.second, screenSize().third) } ?: screenSize()
        val config = DisplayConfigPlanner.config(
            w.toDouble(), h.toDouble(), density.toDouble(), mode = container.display.mode, mirrorFit = container.display.fit,
        ) ?: return
        failure = null
        sasCode = null
        connecting = true
        screen = Screen.STREAM
        lastTarget = targets.firstOrNull()
        currentConfig = config
        viewport.requested = w to h
        videoSize = if (config.mirrorFit == MirrorFit.NATIVE) null else config.w.toInt() to config.h.toInt()
        val current = ++generation
        val next = ViewerSession(trust, deviceName, { decoder.submit(it) }, { post { if (current == generation) onState(it) } },
            { Thread(it, "xdesk-udp").also { t -> t.priority = Thread.MAX_PRIORITY } }, onAgentApproval = { post { agentApproval = it } },
            audioSink = audio.sink)
        session = next
        input = StreamInputRouter(next).also { it.configure(config.w / config.scale.toFloat(), config.h / config.scale.toFloat()) }
        background.execute { next.connect(targets, config, auth) }
    }

    private fun onState(state: ViewerState) {
        when (state) {
            ViewerState.Streaming -> { connecting = false; streaming = true; sasCode = null; startDecoderIfReady(); checkViewport() }
            ViewerState.Connecting -> connecting = true
            ViewerState.Idle -> { connecting = false; streaming = false }
            is ViewerState.Failed -> {
                connecting = false; streaming = false; sasCode = null; agentApproval = null
                decoder.stop()
                failure = ConnectionFailure(state.message, state.code in REPAIRABLE)
                pairTarget = lastTarget
                screen = Screen.HOSTS
                knownHosts = container.knownHosts.all()
            }
        }
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
        decoder.start(target, config.w.toInt(), config.h.toInt(), maxSize)
    }

    private fun onVideoSize(w: Int, h: Int) {
        videoSize = w to h
        if (isNativeMirror) input?.configure(w / MAC_POINT_RATIO, h / MAC_POINT_RATIO)
    }

    fun disconnect() {
        val ending = session ?: return
        endSession()
        session = null
        input = null
        decoder.stop()
        background.execute { ending.disconnect() }
        connecting = false; streaming = false; agentApproval = null
        screen = Screen.HOSTS
        knownHosts = container.knownHosts.all()
    }

    fun forget(id: String) { container.knownHosts.remove(id); knownHosts = container.knownHosts.all() }

    fun answerAgentApproval(allow: Boolean) { session?.answerAgentApproval(allow); agentApproval = null }

    fun refreshStats() {
        val s = session ?: return
        val sound = audio.player.stats.takeIf { it.packets > 0 }?.let { " · tiếng ${it.codec} ${it.estimatedLatencyMs(s.rttMs ?: 0)} ms" }.orEmpty()
        stats = "${decoder.codecName ?: "-"} · ${s.fps} fps · ${s.recvKbps} kbps · RTT ${s.rttMs ?: "-"} ms$sound"
    }

    fun resetIdentity() { container.resetIdentity(); knownHosts = container.knownHosts.all() }

    /**
     * Vùng hiển thị thật (px, sau khi trừ tai thỏ) do màn stream báo. Khác vùng đã xin thì mở lại phiên với đúng cỡ này,
     * để video không bị kéo giãn/cắt; riêng Giống màn hình Mac không đàm phán lại ([ViewportPolicy]).
     */
    fun onViewportChanged(width: Int, height: Int) {
        viewport.actual = width to height
        checkViewport()
    }

    fun clearViewport() { viewport.actual = null }

    private fun checkViewport() {
        val target = session?.connectedTarget ?: lastTarget ?: return
        viewport.schedule(streaming, isNativeMirror) { restartWith(target) }
    }

    /** Đổi kiểu Bản sao rồi kết nối lại (host phải đổi cỡ màn hình nên phải đàm phán lại). */
    fun switchFit(next: MirrorFit) {
        val target = session?.connectedTarget ?: lastTarget ?: return
        container.display.selectFit(next)
        restartWith(target)
    }

    private fun restartWith(target: ViewerTarget) {
        val ending = session ?: return
        endSession()
        background.execute { ending.disconnect() }
        decoder.stop()
        start(listOf(target), ViewerAuth.Automatic)
    }

    /** Vô hiệu mọi việc đang chờ của phiên hiện tại (trạng thái muộn, hẹn mở lại theo viewport) trước khi đóng/mở lại. */
    private fun endSession() { generation++; viewport.cancel(); streaming = false }

    private fun post(block: () -> Unit) { main.post(block) }

    override fun onCleared() {
        endSession()
        session?.disconnect()
        decoder.release()
        background.shutdownNow()
    }

    private companion object {
        const val NATIVE_MAX_EDGE = 2560
        /** Mac Retina: 2 px video mỗi điểm; chỉ dùng để quy ngưỡng/delta cuộn ra điểm host. */
        const val MAC_POINT_RATIO = 2f
        val REPAIRABLE = setOf(TransportErrorCode.PAIRING_REQUIRED, TransportErrorCode.RECONNECT_REFUSED, TransportErrorCode.HOST_KEY_MISMATCH, TransportErrorCode.REVOKED_BY_HOST)
    }
}
