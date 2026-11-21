package vn.xox.xdesk.transport

import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import vn.xox.xdesk.wire.AssembledFrame
import vn.xox.xdesk.wire.Capabilities
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.InputEvent
import vn.xox.xdesk.wire.MediaPacket
import vn.xox.xdesk.wire.MediaPacketType

/**
 * Phía viewer của một kết nối: handshake → UDP → ghép frame (giao cho [frameSink]), ping/pong (ClockSync),
 * `net.report` mỗi 500 ms và `keyframe.request` khi cần. Mọi việc gửi đi chạy trên một executor I/O riêng
 * (Android cấm gửi mạng trên main thread). [connect] chặn thread gọi tới khi xong: gọi từ thread nền.
 * Dùng lại được: sau [disconnect] hoặc lỗi có thể [connect] lại.
 */
class ViewerSession(
    private val trust: ViewerTrust,
    private val deviceName: String,
    private val frameSink: (AssembledFrame) -> Unit,
    private val onState: (ViewerState) -> Unit = {},
    private val threadFactory: (Runnable) -> Thread = { Thread(it, "xdesk-udp") },
    private val nowMs: () -> Long = System::currentTimeMillis,
    onAgentApproval: (AgentApprovalRequest?) -> Unit = {},
    private val audioSink: AudioSink? = null,
    val preferHevc: Boolean = false,
) {
    private val connector = ViewerConnector(trust, deviceName, nowMs)
    private val lock = Any()
    private var io: ScheduledExecutorService? = null
    private var connection: ControlConnection? = null
    private var channel: UdpMediaChannel? = null
    private var inputPump: InputPump? = null
    private var streamId = 0
    private val metrics = SessionMetrics()
    private val approvals = AgentApprovalGate(nowMs, { delayMs, task -> io?.schedule(task, delayMs, TimeUnit.MILLISECONDS) }, onAgentApproval)
    private var lastKeyframeRequestMs = 0L
    private var audioActive = false

    @Volatile var state: ViewerState = ViewerState.Idle
        private set
    @Volatile var connectedHostId: String? = null
        private set
    @Volatile var connectedTarget: ViewerTarget? = null
        private set
    val fps: Int get() = metrics.fps
    val recvKbps: Int get() = metrics.recvKbps
    val rttMs: Long? get() = metrics.rttMs
    val clockOffsetMs: Double? get() = metrics.clockOffsetMs
    val refusedHostId: String? get() = connector.refusedHostId
    /** Sự kiện input chờ host ack (-1 khi chưa streaming). */
    val pendingInputCount: Int get() = inputPump?.pendingCount ?: -1
    val udpStats: UdpChannelStats? get() = channel?.stats
    /** Yêu cầu duyệt agent AI đang chờ (null nếu không có / đã hết hạn / đã trả lời). */
    val pendingAgentApproval: AgentApprovalRequest? get() = approvals.pending

    /** Chặn tới khi streaming hoặc lỗi. Trả `true` nếu streaming. */
    fun connect(candidates: List<ViewerTarget>, config: ControlMessage.DisplayConfig, auth: ViewerAuth = ViewerAuth.Automatic): Boolean {
        synchronized(lock) {
            if (state != ViewerState.Idle && state !is ViewerState.Failed) return false
            setState(ViewerState.Connecting)
        }
        connectedHostId = null
        try {
            establish(candidates, config, auth)
            setState(ViewerState.Streaming)
            return true
        } catch (e: Exception) {
            teardown()
            setState(ViewerState.Failed(describeError(e), (e as? TransportException)?.code))
            return false
        }
    }

    fun disconnect() {
        val conn = connection
        if (conn != null && state == ViewerState.Streaming) {
            try { conn.send(ControlMessage.Bye("viewer closed")) } catch (e: TransportException) { /* kênh đã đóng */ }
        }
        teardown()
        setState(ViewerState.Idle)
    }

    /** Gửi sự kiện input (UDP); bỏ qua khi chưa streaming. Gọi được từ main thread. */
    fun sendInput(events: List<InputEvent>) {
        if (state != ViewerState.Streaming) return
        runIo { inputPump?.submit(events, nowMs()) }
    }

    /** Gửi chuỗi đã gõ xong (IME) qua `input.text`; chuỗi dài chia ≤ 4096 byte. */
    fun sendText(text: String) {
        if (state != ViewerState.Streaming || text.isEmpty()) return
        runIo {
            for (chunk in TextChunker.splitUtf8(text, ControlMessage.InputText.MAX_BYTES)) {
                connection?.send(ControlMessage.InputText(chunk))
            }
        }
    }

    /** Trả lời yêu cầu duyệt trên kênh điều khiển mã hoá; chỉ lần đầu có tác dụng, trả lời sau khi hết hạn bị bỏ. */
    fun answerAgentApproval(allow: Boolean) {
        val request = approvals.take() ?: return
        runIo { connection?.send(ControlMessage.AgentApprove.response(request.id, allow)) }
    }

    fun requestKeyframe() = runIo { requestKeyframeNow() }
    fun hostNowMs(): Long? = metrics.hostNowMs()

    private fun establish(candidates: List<ViewerTarget>, config: ControlMessage.DisplayConfig, auth: ViewerAuth) {
        val host = connector.connect(candidates, auth)
        val conn = host.connection
        connection = conn
        connectedTarget = host.target
        connectedHostId = host.hostId
        val result = ViewerHandshake.run(conn, deviceName, offeredCaps(), config)
        startAudio(result.caps)
        val keys = conn.udpKeys ?: transportError(TransportErrorCode.PROTOCOL_VIOLATION, "thiếu khoá UDP")
        streamId = result.ready.streamId
        val executor = Executors.newSingleThreadScheduledExecutor { Thread(it, "xdesk-io") }
        io = executor
        inputPump = InputPump(streamId, { channel?.sendPacket(it) }, { })
        channel = UdpMediaChannel.connect(
            streamId, conn.remoteAddress, result.ready.udpPort, keys, MediaListener(), { sendResync(it) }, threadFactory,
        )
        val reader = ControlReader(
            conn, { metrics.updateClock(ClockSample(it, ClockSync.wallClockMs())) }, { channel?.handleResync(it) },
            { approvals.receive(it, hostNowMs()) }, { connectedHostId?.let(trust.knownHosts::remove) }, ::fail,
        )
        Thread(reader::run, "xdesk-control").apply { isDaemon = true }.start()
        executor.scheduleWithFixedDelay({ guardedIo { inputPump?.maintain(nowMs()) } }, 50, InputPump.MAINTENANCE_INTERVAL_MS, TimeUnit.MILLISECONDS)
        executor.scheduleWithFixedDelay({ guardedIo { reportNow() } }, 500, 500, TimeUnit.MILLISECONDS)
        executor.execute { pingLoop(100) }
    }

    /** Khả năng viewer đưa ra: audio chỉ khi app có [audioSink]; host chỉ giữ lại nếu thiết bị này được cấp quyền âm thanh. */
    private fun offeredCaps(): Long {
        val video = if (preferHevc) Capabilities.H264 or Capabilities.HEVC else Capabilities.H264
        return if (audioSink == null) video else video or Capabilities.AUDIO_PCM or Capabilities.AUDIO_AAC_ELD
    }

    private fun startAudio(negotiated: Long) {
        val sink = audioSink ?: return
        if (negotiated and (Capabilities.AUDIO_PCM or Capabilities.AUDIO_AAC_ELD) == 0L) return
        try {
            sink.start()
            audioActive = true
        } catch (e: RuntimeException) {
            audioActive = false // không bật được loa: chỉ mất tiếng, hình vẫn chạy
        }
    }

    private fun stopAudio() {
        if (!audioActive) return
        audioActive = false
        audioSink?.stop()
    }

    private fun pingLoop(intervalMs: Long) {
        val executor = io ?: return
        guardedIo { connection?.send(ControlMessage.Ping(ClockSync.wallClockMs())) }
        if (!executor.isShutdown) executor.schedule({ pingLoop(minOf(1000, intervalMs + 100)) }, intervalMs, TimeUnit.MILLISECONDS)
    }

    private fun reportNow() {
        val window = metrics.closeWindow(nowMs()) ?: return
        connection?.send(ControlMessage.NetReport(maxOf(0, rttMs ?: 0), window.lossPermille.toLong(), 0, window.recvKbps.toLong()))
    }

    private fun requestKeyframeNow() {
        val now = nowMs()
        if (now - lastKeyframeRequestMs < KEYFRAME_REQUEST_MIN_GAP_MS) return
        lastKeyframeRequestMs = now
        connection?.send(ControlMessage.KeyframeRequest(streamId))
    }
    private fun sendResync(resync: ControlMessage.RekeyResync) = runIo { connection?.send(resync) }
    private fun runIo(task: () -> Unit) {
        val executor = io ?: return
        if (!executor.isShutdown) executor.execute { guardedIo(task) }
    }

    /** Lỗi gửi trên executor I/O: kết nối đã hỏng, đường đọc sẽ báo `fail`; ở đây chỉ chặn để executor không chết. */
    private fun guardedIo(task: () -> Unit) {
        try { task() } catch (e: TransportException) { /* đóng kênh đã được reader xử lý */ } catch (e: vn.xox.xdesk.wire.WireException) { /* gói sai: bỏ */ }
    }

    private fun fail(message: String, code: TransportErrorCode?) {
        synchronized(lock) {
            if (state != ViewerState.Streaming) return
            setState(ViewerState.Failed(message, code))
        }
        teardown()
    }

    private fun teardown() {
        approvals.clear()
        stopAudio()
        io?.shutdownNow()
        io = null
        channel?.close()
        channel = null
        connection?.close()
        connection = null
        inputPump = null
        metrics.reset()
    }

    private fun setState(newState: ViewerState) {
        state = newState
        onState(newState)
    }

    private inner class MediaListener : UdpMediaListener {
        override fun onFrame(frame: AssembledFrame) {
            metrics.recordFrame(frame.frameNo, frame.data.size)
            frameSink(frame)
        }

        override fun onKeyframeNeeded() = runIo { requestKeyframeNow() }
        override fun onPacket(packet: MediaPacket) {
            if (packet.header.type == MediaPacketType.AUDIO) audioSink?.onPacket(packet) else runIo { inputPump?.handleAck(packet) }
        }
        override fun onLinkLost() = fail(TransportErrorCode.LINK_LOST.message, TransportErrorCode.LINK_LOST)
    }

    companion object {
        const val KEYFRAME_REQUEST_MIN_GAP_MS = 500L
    }
}
