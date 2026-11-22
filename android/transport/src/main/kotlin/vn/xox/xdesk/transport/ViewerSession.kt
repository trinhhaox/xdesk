package vn.xox.xdesk.transport

import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.util.UUID
import java.util.Collections
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import vn.xox.xdesk.wire.AssembledFrame
import vn.xox.xdesk.wire.Capabilities
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.DisplayInfo
import vn.xox.xdesk.wire.InputEvent
import vn.xox.xdesk.wire.MediaKeyKind
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
    onAgentHelp: (AgentHelpRequest?) -> Unit = {},
    private val audioSink: AudioSink? = null,
    val preferHevc: Boolean = false,
    private val clipboardAccess: ClipboardAccess? = null,
    private val preferMediaOverTcp: Boolean = false,
    private val fileTempDir: File = File(System.getProperty("java.io.tmpdir"), "xdesk-transfers"),
    private val onDisplayList: (List<DisplayInfo>) -> Unit = {},
    private val onFileProgress: (FileTransferProgress?) -> Unit = {},
    private val onFileReceived: (FileTransferCompletion) -> Unit = {},
    private val onFileError: (String, String) -> Unit = { _, _ -> },
    private val onUnlockResult: (ControlMessage.SystemUnlockResult) -> Unit = {},
    private val unlockSigner: UnlockSigner? = null,
    private val onLockResult: (ControlMessage.SystemLockResult) -> Unit = {},
    private val onHostState: (ControlMessage.HostState) -> Unit = {},
    /** Gọi trên thread đọc control mỗi khi host gửi `window.selected` (kể cả `ok == false`); đẩy sang UI thread khi cần. */
    private val onWindowSelected: (ControlMessage.WindowSelected) -> Unit = {},
) {
    private val connector = ViewerConnector(trust, deviceName, nowMs)
    @Volatile private var connectedHostInfo: UnlockHostInfo? = null
    private val unlockClient = UnlockAttestationClient(
        unlockSigner, trust.identity.publicKey, { connectedHostInfo }, nowMs, { msg -> runIo { connection?.send(msg) } }, onUnlockResult,
    )
    private val lock = Any()
    private var io: ScheduledExecutorService? = null
    private var connection: ControlConnection? = null
    private var channel: UdpMediaChannel? = null
    private var inputPump: InputPump? = null
    private var clipboardSync: ClipboardSync? = null
    @Volatile private var activeSendingFileId: String? = null
    private val cancelledFileIds = Collections.synchronizedSet(HashSet<String>())
    @Volatile private var hostDeniedSending = false
    private val fileReceiver = FileTransferReceiver(fileTempDir, onFileProgress, onFileReceived, onFileError)
    private var streamId = 0
    private val metrics = SessionMetrics()
    private val approvals = AgentApprovalGate(nowMs, { delayMs, task -> io?.schedule(task, delayMs, TimeUnit.MILLISECONDS) }, onAgentApproval)
    private val agentHelps = AgentHelpGate(onAgentHelp)
    private val reconfigureLock = Any()
    private var pendingReconfigure: Pair<Long, (Boolean) -> Unit>? = null
    private val earlyReadyIds = HashSet<Long>()
    private var lastKeyframeRequestMs = 0L
    private var audioActive = false

    @Volatile var state: ViewerState = ViewerState.Idle
        private set
    @Volatile var negotiatedCaps: Long = 0L
        private set
    val supportsHotReconfigure: Boolean get() = (negotiatedCaps and Capabilities.HOT_RECONFIGURE) != 0L
    val supportsVideoPause: Boolean get() = (negotiatedCaps and Capabilities.VIDEO_PAUSE) != 0L
    val supportsFileTransfer: Boolean get() = (negotiatedCaps and Capabilities.FILE_TRANSFER) != 0L
    /** Host cho phép chọn/kéo/đổi cỡ cửa sổ Mac (cần quyền `input` + Accessibility); UI ẩn "Chỉnh cửa sổ" khi `false`. */
    val supportsWindowControl: Boolean get() = (negotiatedCaps and Capabilities.WINDOW_CONTROL) != 0L
    val audioAvailable: Boolean get() = state == ViewerState.Streaming && audioActive
    val clipboardAvailable: Boolean
        get() = state == ViewerState.Streaming &&
            (negotiatedCaps and Capabilities.CLIPBOARD) != 0L &&
            clipboardSync != null
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
    /** Yêu cầu hỗ trợ agent AI đang chờ (null nếu không có / đã giải quyết). */
    val pendingAgentHelp: AgentHelpRequest? get() = agentHelps.pending

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

    fun resolveAgentHelp(requestId: String) {
        agentHelps.take()
        runIo { connection?.send(ControlMessage.AgentHelp.resolve(requestId)) }
    }

    fun sendSystemLock() {
        runIo { connection?.send(ControlMessage.SystemLock) }
    }

    /** Mở cờ chờ thử thách (30 s), gửi lại khoá công khai rồi xin thử thách; Face ID/vân tay hiện khi ký thử thách. */
    fun sendSystemUnlock() {
        unlockClient.arm()
        runIo {
            unlockClient.registerKey(negotiatedCaps)
            connection?.send(ControlMessage.SystemUnlock())
        }
    }

    fun existingUnlockPublicKey(): ByteArray? = unlockSigner?.existingPublicKey()

    fun sendMediaKey(key: MediaKeyKind) {
        if (state != ViewerState.Streaming) return
        runIo { connection?.send(ControlMessage.MediaKey(key)) }
    }

    /** Chọn cửa sổ trên cùng tại điểm (x, y) của luồng video đang xem; kết quả về [onWindowSelected]. */
    fun pickWindow(x: Double, y: Double) = sendWindowMessage(ControlMessage.WindowPick(x, y))

    /** Dời / đổi cỡ / xếp cửa sổ đã chọn (`WindowAdjust.move/resize/preset`); host trả `window.selected`. Viewer nên gộp theo khung hình. */
    fun adjustWindow(adjust: ControlMessage.WindowAdjust) = sendWindowMessage(adjust)

    private fun sendWindowMessage(message: ControlMessage) {
        if (state != ViewerState.Streaming || !supportsWindowControl) return
        runIo { connection?.send(message) }
    }

    fun setVideoPaused(paused: Boolean) {
        if (state != ViewerState.Streaming || !supportsVideoPause) return
        runIo {
            connection?.send(if (paused) ControlMessage.VideoPause(streamId) else ControlMessage.VideoResume(streamId))
        }
    }

    /** Đổi cấu hình màn hình nóng trong phiên đang mở; trả `false` qua [onResult] nếu host cũ hoặc lỗi. */
    fun reconfigureDisplay(config: ControlMessage.DisplayConfig, onResult: (Boolean) -> Unit) {
        val executor = io
        if (state != ViewerState.Streaming || !supportsHotReconfigure || executor == null || executor.isShutdown) {
            onResult(false)
            return
        }
        executor.execute {
            val conn = connection
            if (conn == null || state != ViewerState.Streaming) {
                onResult(false)
                return@execute
            }
            try {
                val reqId = conn.send(ControlMessage.DisplayReconfigure(config))
                var immediate: Boolean? = null
                synchronized(reconfigureLock) {
                    if (earlyReadyIds.remove(reqId)) {
                        immediate = true
                    } else {
                        pendingReconfigure?.second?.invoke(false)
                        pendingReconfigure = reqId to onResult
                    }
                }
                if (immediate == true) {
                    onResult(true)
                } else {
                    executor.schedule({ finishReconfigure(reqId, false) }, RECONFIGURE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                }
            } catch (e: TransportException) {
                onResult(false)
            } catch (e: vn.xox.xdesk.wire.WireException) {
                onResult(false)
            }
        }
    }

    private fun finishReconfigure(id: Long, ok: Boolean) {
        val callback: ((Boolean) -> Unit)? = synchronized(reconfigureLock) {
            val pending = pendingReconfigure
            if (pending != null && pending.first == id) {
                pendingReconfigure = null
                pending.second
            } else {
                if (ok) earlyReadyIds.add(id)
                null
            }
        }
        callback?.invoke(ok)
    }

    fun cancelFileTransfer() {
        val sendingId = activeSendingFileId
        if (sendingId != null) {
            cancelledFileIds.add(sendingId)
            return
        }
        val active = fileReceiver
        active.cancelAll()
    }

    fun sendFile(name: String, totalBytes: Long, openStream: () -> InputStream?, onFinished: (Boolean, String?) -> Unit = { _, _ -> }) {
        val conn = connection ?: return onFinished(false, "Chưa kết nối tới Mac")
        if (!supportsFileTransfer) return onFinished(false, FileTransferDenial.MESSAGE)
        runIo {
            val id = UUID.randomUUID().toString()
            activeSendingFileId = id
            try {
                val stream = openStream() ?: throw IllegalStateException("Không mở được luồng tệp")
                val completed = stream.use { input ->
                    FileTransferSender.sendFile(
                        id = id,
                        fileName = name,
                        totalBytes = totalBytes,
                        input = input,
                        connection = conn,
                        isCancelled = { id in cancelledFileIds },
                        onProgress = onFileProgress,
                    )
                }
                onFinished(completed, if (completed) null else if (hostDeniedSending) FileTransferDenial.MESSAGE else "cancelled")
            } catch (e: Exception) {
                onFileProgress(null)
                onFinished(false, e.message)
            } finally {
                if (activeSendingFileId == id) activeSendingFileId = null
                cancelledFileIds.remove(id)
                hostDeniedSending = false
            }
        }
    }

    fun sendFile(name: String, bytes: ByteArray) {
        sendFile(name, bytes.size.toLong(), { ByteArrayInputStream(bytes) })
    }

    /** Chủ động đọc clipboard Android hiện tại và gửi sang Mac (trả về `.Disabled` nếu chưa cấp quyền clipboard). */
    fun sendClipboard(onResult: (ClipboardSendOutcome) -> Unit) {
        val sync = clipboardSync
        val executor = io
        if (sync == null || !clipboardAvailable || executor == null || executor.isShutdown) {
            onResult(ClipboardSendOutcome.Disabled)
            return
        }
        executor.execute {
            val outcome = sync.sendCurrent()
            onResult(outcome)
        }
    }

    fun requestKeyframe() = runIo { requestKeyframeNow() }
    fun hostNowMs(): Long? = metrics.hostNowMs()

    private fun establish(candidates: List<ViewerTarget>, config: ControlMessage.DisplayConfig, auth: ViewerAuth) {
        val host = connector.connect(candidates, auth)
        val conn = host.connection
        connection = conn
        connectedTarget = host.target
        connectedHostId = host.hostId
        connectedHostInfo = UnlockHostInfo(host.hostKey, host.hostName)
        unlockClient.reset()
        val result = ViewerHandshake.run(conn, deviceName, offeredCaps(), config)
        negotiatedCaps = result.caps
        if (clipboardAccess != null && (result.caps and Capabilities.CLIPBOARD) != 0L) {
            val transport = object : ClipboardTransport {
                override fun sendClip(message: ControlMessage) { conn.send(message) }
                override fun sendClipData(header: ControlMessage.ClipData, payload: ByteArray) { conn.sendClipData(header, payload) }
            }
            clipboardSync = ClipboardSync(transport, clipboardAccess, nowMs = nowMs) { true }
        } else {
            clipboardSync = null
        }
        startAudio(result.caps)
        val useMediaOverTcp = (result.caps and Capabilities.MEDIA_OVER_TCP) != 0L
        streamId = result.ready.streamId
        val executor = Executors.newSingleThreadScheduledExecutor { Thread(it, "xdesk-io") }
        io = executor
        inputPump = InputPump(streamId, { channel?.sendPacket(it) }, { })
        channel = if (useMediaOverTcp) {
            UdpMediaChannel.overTcp(streamId, MediaListener(), { conn.sendMediaOverTcp(it) }, nowMs)
        } else {
            val keys = conn.udpKeys ?: transportError(TransportErrorCode.PROTOCOL_VIOLATION, "thiếu khoá UDP")
            UdpMediaChannel.connect(
                streamId, conn.remoteAddress, result.ready.udpPort, keys, MediaListener(), { sendResync(it) }, threadFactory,
            )
        }
        val reader = ControlReader(
            conn, { metrics.updateClock(ClockSample(it, ClockSync.wallClockMs())) }, { channel?.handleResync(it) },
            { approvals.receive(it, hostNowMs()) }, { agentHelps.receive(it) }, { connectedHostId?.let(trust.knownHosts::remove) }, ::fail,
            onDisplayReady = { id, _ -> finishReconfigure(id, true) },
            onMediaOverTcp = { channel?.ingest(it) },
            onBulk = { bytes -> if (!fileReceiver.handleBulk(bytes)) clipboardSync?.handleBulk(bytes) },
            onClipboard = { clipboardSync?.handle(it) },
            onFileTransfer = { msg -> handleIncomingFileMessage(msg) },
            onDisplayList = { list -> onDisplayList(list.displays) },
            onUnlockResult = onUnlockResult,
            onUnlockChallenge = unlockClient::answer,
            onLockResult = onLockResult,
            onHostState = onHostState,
            onWindowSelected = onWindowSelected,
        )
        Thread(reader::run, "xdesk-control").apply { isDaemon = true }.start()
        if (useMediaOverTcp) {
            executor.execute { guardedIo { channel?.sendProbe() } }
        }
        executor.execute { guardedIo { unlockClient.registerKey(result.caps) } }
        executor.scheduleWithFixedDelay({ guardedIo { inputPump?.maintain(nowMs()) } }, 50, InputPump.MAINTENANCE_INTERVAL_MS, TimeUnit.MILLISECONDS)
        executor.scheduleWithFixedDelay({ guardedIo { reportNow() } }, 500, 500, TimeUnit.MILLISECONDS)
        executor.execute { pingLoop(100) }
    }

    private fun handleIncomingFileMessage(message: ControlMessage) {
        when (message) {
            is ControlMessage.FileStart -> fileReceiver.handleStart(message)
            is ControlMessage.FileChunk -> fileReceiver.handleChunkHeader(message)
            is ControlMessage.FileDone -> fileReceiver.handleDone(message)
            is ControlMessage.FileCancel -> {
                if (activeSendingFileId == message.id) {
                    if (message.reason == FileTransferDenial.REASON) hostDeniedSending = true
                    cancelledFileIds.add(message.id)
                } else {
                    fileReceiver.handleCancel(message)
                }
            }
            else -> Unit
        }
    }

    /** Khả năng viewer đưa ra: audio chỉ khi app có [audioSink]; clipboard khi có [clipboardAccess]; MediaOverTcp khi đi qua USB/loopback. */
    private fun offeredCaps(): Long {
        var caps = (if (preferHevc) Capabilities.H264 or Capabilities.HEVC else Capabilities.H264) or
            Capabilities.HOT_RECONFIGURE or Capabilities.VIDEO_PAUSE or
            Capabilities.FILE_TRANSFER or Capabilities.REMOTE_UNLOCK or Capabilities.MEDIA_KEYS or Capabilities.MULTI_DISPLAY or
            Capabilities.WINDOW_CONTROL
        if (audioSink != null) caps = caps or Capabilities.AUDIO_PCM or Capabilities.AUDIO_AAC_ELD
        if (clipboardAccess != null) caps = caps or Capabilities.CLIPBOARD
        if (unlockClient.offered) caps = caps or Capabilities.UNLOCK_ATTESTATION
        if (preferMediaOverTcp) caps = caps or Capabilities.MEDIA_OVER_TCP
        return caps
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
        val pendingCallback = synchronized(reconfigureLock) {
            earlyReadyIds.clear()
            pendingReconfigure?.second.also { pendingReconfigure = null }
        }
        pendingCallback?.invoke(false)
        negotiatedCaps = 0L
        activeSendingFileId?.let { cancelledFileIds.add(it) }
        activeSendingFileId = null
        fileReceiver.cancelAll()
        clipboardSync?.reset()
        clipboardSync = null
        approvals.clear()
        agentHelps.clear()
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
        const val RECONFIGURE_TIMEOUT_MS = 5_000L
    }
}
