package vn.xox.xdesk.transport

import java.io.Closeable
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread
import vn.xox.xdesk.crypto.DatagramSender
import vn.xox.xdesk.crypto.DeviceIdentity
import vn.xox.xdesk.crypto.DeviceRole
import vn.xox.xdesk.crypto.HandshakeFrame
import vn.xox.xdesk.crypto.HandshakePayload
import vn.xox.xdesk.crypto.NoiseHandshakeState
import vn.xox.xdesk.crypto.NoisePattern
import vn.xox.xdesk.crypto.NoiseRole
import vn.xox.xdesk.crypto.SessionKeys
import vn.xox.xdesk.crypto.StreamReceiver
import vn.xox.xdesk.crypto.StreamSender
import vn.xox.xdesk.crypto.sessionKeys
import vn.xox.xdesk.wire.ControlEnvelope
import vn.xox.xdesk.wire.ControlFrame
import vn.xox.xdesk.wire.ControlFrameCodec
import vn.xox.xdesk.wire.ControlFrameDecoder
import vn.xox.xdesk.wire.ControlFrameKind
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.ControlMessageCodec
import vn.xox.xdesk.wire.MediaPacket

/** Host giả (responder Noise thật, JVM) cho test state machine của viewer qua TCP/UDP loopback. */
class FakeHost(val identity: DeviceIdentity = DeviceIdentity.generate()) : Closeable {
    val token = ByteArray(32).also(SecureRandom()::nextBytes)
    val knownViewers = CopyOnWriteArrayList<ByteArray>()
    val received = CopyOnWriteArrayList<ControlMessage>()
    val receivedMediaOverTcp = CopyOnWriteArrayList<MediaPacket>()
    val receivedBulk = CopyOnWriteArrayList<ByteArray>()
    @Volatile var revokeAfterReady = false
    @Volatile var rekeyAfterHello = false
    @Volatile var sessionKeys: SessionKeys? = null
    private val server = ServerSocket(0, 4, InetAddress.getLoopbackAddress())
    private val udp = DatagramSocket(0, InetAddress.getLoopbackAddress())
    val port: Int get() = server.localPort
    val udpPort: Int get() = udp.localPort
    private var sender: StreamSender? = null
    private val sendLock = Any()
    @Volatile private var push: ((ControlMessage, Long) -> Unit)? = null
    @Volatile private var pushTcpMedia: ((MediaPacket) -> Unit)? = null
    @Volatile private var pushBulkFrame: ((ByteArray) -> Unit)? = null

    init { thread(isDaemon = true) { while (!server.isClosed) { runCatching { serve(server.accept()) } } } }

    private fun serve(socket: Socket) {
        thread(isDaemon = true) {
            try { session(socket) } catch (e: Exception) { /* viewer đóng/ngắt: kết thúc phiên */ } finally { socket.close() }
        }
    }

    private fun session(socket: Socket) {
        val decoder = ControlFrameDecoder()
        val buf = ByteArray(8192)
        fun frame(): ControlFrame {
            while (true) {
                decoder.next()?.let { return it }
                val n = socket.getInputStream().read(buf)
                if (n < 0) error("eof")
                decoder.append(buf.copyOf(n))
            }
        }
        fun noise(): HandshakeFrame.Noise = HandshakeFrame.decode(frame().payload) as HandshakeFrame.Noise
        val begin = HandshakeFrame.decode(frame().payload) as HandshakeFrame.Begin
        if (begin.pattern == NoisePattern.XX) frame()
        val state = NoiseHandshakeState(begin.pattern, NoiseRole.RESPONDER, identity.privateKey(), null, if (begin.pattern == NoisePattern.XX_PSK3) token else null)
        val first = state.readMessage(noise().message)
        if (begin.pattern == NoisePattern.IK) {
            val remote = state.remoteStaticKey ?: return
            if (knownViewers.none { it.contentEquals(remote) }) return
            check(HandshakePayload.decode(first).role == DeviceRole.VIEWER)
        }
        val reply = HandshakePayload(DeviceRole.HOST, "FakeHost").encode()
        socket.getOutputStream().write(ControlFrameCodec.encode(ControlFrame(ControlFrameKind.HANDSHAKE, HandshakeFrame.Noise(state.writeMessage(reply)).encode())))
        if (begin.pattern != NoisePattern.IK) {
            state.readMessage(noise().message)
            state.remoteStaticKey?.let { knownViewers += it }
        }
        val keys = state.sessionKeys().also { sessionKeys = it }
        val tx = StreamSender(keys.tcpSend).also { sender = it }
        val rx = StreamReceiver(keys.tcpReceive)
        decoder.extraBulkAllowance = 16
        fun sendSealed(kind: ControlFrameKind, plain: ByteArray) = synchronized(sendLock) {
            val ct = tx.seal(kind.raw, plain)
            val len = 1 + ct.size
            socket.getOutputStream().write(byteArrayOf((len ushr 24).toByte(), (len ushr 16).toByte(), (len ushr 8).toByte(), len.toByte(), kind.raw.toByte()) + ct)
            socket.getOutputStream().flush()
        }
        fun send(message: ControlMessage, id: Long = 0) = sendSealed(
            ControlFrameKind.CONTROL, ControlMessageCodec.encode(ControlEnvelope(id, message)),
        )
        push = ::send
        pushTcpMedia = { sendSealed(ControlFrameKind.MEDIA_OVER_TCP, it.encode()) }
        pushBulkFrame = { sendSealed(ControlFrameKind.BULK, it) }
        if (begin.pattern != NoisePattern.IK) send(ControlMessage.PairResult(true))
        while (true) {
            val f = frame()
            val plain = rx.open(f.kind.raw, f.payload)
            when (f.kind) {
                ControlFrameKind.MEDIA_OVER_TCP -> {
                    receivedMediaOverTcp += MediaPacket.decode(plain)
                    continue
                }
                ControlFrameKind.BULK -> {
                    receivedBulk += plain
                    continue
                }
                ControlFrameKind.HANDSHAKE -> continue
                ControlFrameKind.CONTROL -> Unit
            }
            val envelope = ControlMessageCodec.decode(plain)
            val message = envelope.message
            if (message == ControlMessage.Rekey) { rx.rekey(); continue }
            received += message
            when (message) {
                is ControlMessage.Hello -> send(ControlMessage.Welcome("1.0", "s-test", message.caps), envelope.id)
                is ControlMessage.DisplayConfig -> {
                    send(ControlMessage.DisplayReady(udpPort, 1), envelope.id)
                    if (revokeAfterReady) send(ControlMessage.Reject(ControlMessage.Reject.REASON_REVOKED))
                }
                is ControlMessage.Ping -> send(ControlMessage.Pong(message.t0, message.t0 + 1, message.t0 + 1), envelope.id)
                else -> Unit
            }
        }
    }

    /** Gửi chủ động một message điều khiển (đã mã hoá) tới viewer đang kết nối. */
    fun push(message: ControlMessage, id: Long = 0) = checkNotNull(push) { "chưa có phiên" }(message, id)

    /** Gửi gói media qua frame TCP 0x04 (`MediaOverTcp`). */
    fun pushMediaOverTcp(packet: MediaPacket) = checkNotNull(pushTcpMedia) { "chưa có phiên" }(packet)

    /** Gửi một frame bulk qua kênh control mã hoá. */
    fun pushBulk(bytes: ByteArray) = checkNotNull(pushBulkFrame) { "chưa có phiên" }(bytes)

    /** Chờ probe của viewer rồi gửi `datagrams` (đã mã hoá bằng khoá UDP chiều host→viewer). */
    fun sendUdp(build: (DatagramSender) -> List<ByteArray>, timeoutMs: Int = 3000): DatagramPacket {
        udp.soTimeout = timeoutMs
        val probe = DatagramPacket(ByteArray(2048), 2048)
        udp.receive(probe)
        val keys = checkNotNull(sessionKeys)
        val out = build(DatagramSender(keys.udpSend))
        out.forEach { udp.send(DatagramPacket(it, it.size, probe.socketAddress)) }
        return probe
    }

    override fun close() {
        server.close()
        udp.close()
    }
}
