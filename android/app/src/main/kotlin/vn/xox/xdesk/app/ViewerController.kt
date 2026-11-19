package vn.xox.xdesk.app

import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import java.util.concurrent.Executors
import vn.xox.xdesk.app.discovery.DiscoveredHost
import vn.xox.xdesk.crypto.CryptoException
import vn.xox.xdesk.crypto.PairingURI
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

enum class Screen { HOSTS, PAIR, STREAM, SECURITY }

/** Kết quả hiển thị của lần kết nối gần nhất. `repairable` = nên đề nghị "Ghép đôi lại". */
data class ConnectionFailure(val message: String, val repairable: Boolean)

/** Trạng thái UI + luồng kết nối. Việc mạng chạy trên một thread nền; trạng thái Compose chỉ ghi từ main thread. */
class ViewerController(private val container: AppContainer, private val deviceName: String, private val screenSize: () -> Triple<Int, Int, Float>) : ViewModel() {
    private val main = Handler(Looper.getMainLooper())
    private val background = Executors.newSingleThreadExecutor { Thread(it, "xdesk-connect") }
    private val decoder = VideoDecoder(onNeedKeyframe = { session?.requestKeyframe() }, onError = { post { failure = ConnectionFailure(it, false) } })
    private val audio = AppAudio()
    private var session: ViewerSession? = null
    private var surface: Surface? = null
    private var lastTarget: ViewerTarget? = null
    private var currentConfig: ControlMessage.DisplayConfig? = null

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
    var input: StreamInputRouter? = null
        private set

    val display: DisplaySettingsStore get() = container.display
    val trust: ViewerTrust? get() = container.trust()
    val identityError: String? get() = container.identityError
    val fingerprint: String? get() = container.identity?.fingerprint

    fun updateHosts(list: List<DiscoveredHost>) = post { hosts = list }

    fun connect(target: ViewerTarget) = start(listOf(target), ViewerAuth.Automatic)

    fun connectManual(text: String) {
        val target = ViewerTarget.parse(text) ?: return run { failure = ConnectionFailure("Địa chỉ phải có dạng host:port", false) }
        connect(target)
    }

    fun pairWithQr(text: String) {
        val uri = try { PairingURI.parse(text) } catch (e: CryptoException) {
            failure = ConnectionFailure("Mã QR không phải của Xdesk", false)
            return
        }
        start(uri.addresses.mapNotNull(ViewerTarget::parse), ViewerAuth.Qr(uri))
    }

    /** Mở màn ghép đôi, nhớ `target` (host vừa chọn hoặc nhập tay; null = chỉ quét QR). */
    fun openPairing(target: ViewerTarget?) {
        pairTarget = target
        screen = Screen.PAIR
    }

    fun pairWithSas(target: ViewerTarget) = start(listOf(target), ViewerAuth.Sas { code -> post { sasCode = code } })

    private fun start(targets: List<ViewerTarget>, auth: ViewerAuth) {
        val trust = trust ?: return run { failure = ConnectionFailure(identityError.orEmpty(), false) }
        val (w, h, density) = screenSize()
        val config = DisplayConfigPlanner.config(
            w.toDouble(), h.toDouble(), density.toDouble(), mode = container.display.mode, mirrorFit = container.display.fit,
        ) ?: return
        failure = null
        sasCode = null
        connecting = true
        screen = Screen.STREAM
        lastTarget = targets.firstOrNull()
        currentConfig = config
        val next = ViewerSession(trust, deviceName, { decoder.submit(it) }, { post { onState(it) } },
            { Thread(it, "xdesk-udp").also { t -> t.priority = Thread.MAX_PRIORITY } }, onAgentApproval = { post { agentApproval = it } },
            audioSink = audio.sink)
        session = next
        input = StreamInputRouter(next).also { it.configure(config.w / config.scale.toFloat(), config.h / config.scale.toFloat()) }
        background.execute { next.connect(targets, config, auth) }
    }

    private fun onState(state: ViewerState) {
        when (state) {
            ViewerState.Streaming -> { connecting = false; streaming = true; sasCode = null; startDecoderIfReady() }
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

    private fun startDecoderIfReady() {
        val target = surface ?: return
        val config = currentConfig ?: return
        if (!streaming) return
        decoder.recorder = container.streamRecorder()
        decoder.start(target, config.w.toInt(), config.h.toInt())
    }

    fun disconnect() {
        val ending = session ?: return
        session = null
        input = null
        decoder.stop()
        background.execute { ending.disconnect() }
        connecting = false; streaming = false; agentApproval = null
        screen = Screen.HOSTS
        knownHosts = container.knownHosts.all()
    }

    fun forget(id: String) {
        container.knownHosts.remove(id)
        knownHosts = container.knownHosts.all()
    }

    fun answerAgentApproval(allow: Boolean) {
        session?.answerAgentApproval(allow)
        agentApproval = null
    }

    fun refreshStats() {
        val s = session ?: return
        val sound = audio.player.stats.takeIf { it.packets > 0 }?.let { " · tiếng ${it.codec} ${it.estimatedLatencyMs(s.rttMs ?: 0)} ms" }.orEmpty()
        stats = "${decoder.codecName ?: "-"} · ${s.fps} fps · ${s.recvKbps} kbps · RTT ${s.rttMs ?: "-"} ms$sound"
    }

    fun resetIdentity() {
        container.resetIdentity()
        knownHosts = container.knownHosts.all()
    }

    /** Xoay máy: khi chiều (ngang/dọc) của bề mặt khác chiều đã cấu hình host thì mở lại phiên với `display.config` mới (như bản iOS). */
    fun onSurfaceResized(width: Int, height: Int) {
        val config = currentConfig ?: return
        if (!streaming || (width > height) == (config.w > config.h)) return
        val target = session?.connectedTarget ?: lastTarget ?: return
        main.removeCallbacks(restart)
        restart = Runnable { restartWith(target) }
        main.postDelayed(restart, ROTATION_SETTLE_MS)
    }

    private fun restartWith(target: ViewerTarget) {
        val ending = session ?: return
        background.execute { ending.disconnect() }
        decoder.stop()
        start(listOf(target), ViewerAuth.Automatic)
    }

    private var restart = Runnable { }

    private fun post(block: () -> Unit) { main.post(block) }

    override fun onCleared() {
        session?.disconnect()
        decoder.release()
        background.shutdownNow()
    }

    private companion object {
        const val ROTATION_SETTLE_MS = 600L
        val REPAIRABLE = setOf(TransportErrorCode.PAIRING_REQUIRED, TransportErrorCode.RECONNECT_REFUSED, TransportErrorCode.HOST_KEY_MISMATCH, TransportErrorCode.REVOKED_BY_HOST)
    }
}
