package vn.xox.xdesk.transport

import java.io.Closeable
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.DatagramChannel
import java.nio.channels.Selector
import vn.xox.xdesk.crypto.CryptoErrorCode
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.FrameOrderGate
import vn.xox.xdesk.wire.MediaHeader
import vn.xox.xdesk.wire.MediaPacket
import vn.xox.xdesk.wire.MediaPacketType
import vn.xox.xdesk.wire.NackTracker
import vn.xox.xdesk.wire.Reassembler
import vn.xox.xdesk.wire.WireException

/**
 * Kênh media UDP phía viewer: gửi `probe` định kỳ tới khi nghe được host, ghép frame, tự NACK, mã hoá từng datagram.
 * Lỗi giải mã chỉ bị đếm, không bao giờ đóng kênh (M4). Một thread I/O dùng `Selector` chu kỳ 10 ms.
 */
class UdpMediaChannel private constructor(
    private val streamId: Int,
    private val channel: DatagramChannel,
    keys: UdpKeys,
    private val listener: UdpMediaListener,
    private val resyncSink: (ControlMessage.RekeyResync) -> Unit,
    private val nowMs: () -> Long,
) : Closeable {
    private val probe = MediaPacket(MediaHeader(MediaPacketType.PROBE, streamId, 0), ByteArray(0))
    private val health = LinkHealth(nowMs)
    private val cipher = UdpDatagramCipher(keys)
    private val sendLock = Any()
    private val selector: Selector = Selector.open()
    private val reassembler = Reassembler()
    private val frameGate = FrameOrderGate()
    private val nackTracker = NackTracker()
    private var heardFromHost = false
    private var lastPunchMs = 0L
    @Volatile private var closed = false
    private lateinit var thread: Thread

    val stats = UdpChannelStats()

    val localPort: Int get() = (channel.localAddress as InetSocketAddress).port

    /** Gửi một gói (input...), mã hoá và rekey khi tới hạn. */
    fun sendPacket(packet: MediaPacket) {
        if (closed) transportError(TransportErrorCode.NO_PEER)
        val bytes = synchronized(sendLock) {
            if (cipher.needsRekey) {
                cipher.rekey()
                resyncSink(ControlMessage.RekeyResync(cipher.sendEpoch, false))
            }
            cipher.seal(packet)
        }
        try {
            channel.write(ByteBuffer.wrap(bytes))
        } catch (e: IOException) {
            transportError(TransportErrorCode.CONNECTION_FAILED, e.message, e)
        }
    }

    /** `rekey.resync` từ host (đã xác thực qua TCP): `ask` → báo epoch gửi của ta; ngược lại kéo khoá nhận lên epoch của host. */
    fun handleResync(resync: ControlMessage.RekeyResync) {
        if (resync.ask) {
            resyncSink(ControlMessage.RekeyResync(cipher.sendEpoch, false))
            return
        }
        try {
            cipher.resync(resync.epoch)
            health.unknownEpochCount = 0
        } catch (e: vn.xox.xdesk.crypto.CryptoException) {
            stats.malformedPacketCount++
        }
    }

    private fun runLoop() {
        val buffer = ByteBuffer.allocate(MAX_DATAGRAM)
        while (!closed) {
            try {
                selector.select(POLL_INTERVAL_MS)
                if (closed) return
                selector.selectedKeys().clear()
                while (true) {
                    buffer.clear()
                    if (channel.receive(buffer) == null) break
                    buffer.flip()
                    handleDatagram(ByteArray(buffer.remaining()).also(buffer::get))
                }
                tick()
                maintain()
            } catch (e: IOException) {
                if (!closed) { listener.onLinkLost(); return }
            }
        }
    }

    private fun handleDatagram(bytes: ByteArray) {
        stats.datagramsReceived++
        val packet = try {
            cipher.open(bytes)
        } catch (e: DatagramRejection) {
            if (e.code == CryptoErrorCode.unknownEpoch) health.unknownEpochCount++
            if (e.countsAsRejected) stats.rejectedDatagramCount++
            return
        } catch (e: WireException) {
            stats.malformedPacketCount++
            return
        }
        health.markValid()
        heardFromHost = true
        handle(packet)
    }

    private fun handle(packet: MediaPacket) {
        when {
            packet.header.type == MediaPacketType.PROBE -> Unit
            packet.header.type == MediaPacketType.VIDEO && packet.header.streamId == streamId -> try {
                val now = nowMs()
                reassembler.ingest(packet, now)?.let { stats.framesAssembled++; publish(frameGate.push(it, now)) }
            } catch (e: WireException) {
                stats.malformedPacketCount++
            }
            packet.header.type == MediaPacketType.VIDEO || packet.header.type == MediaPacketType.NACK -> Unit
            else -> listener.onPacket(packet)
        }
    }

    private fun publish(out: FrameOrderGate.Output) {
        out.skipTo?.let(reassembler::abandonBefore)
        for (frame in out.frames) listener.onFrame(frame)
        if (out.keyframeNeeded) listener.onKeyframeNeeded()
    }

    /** Mỗi 10 ms: punch (nếu chưa nghe được host), NACK và bỏ frame quá hạn. */
    private fun tick() {
        val now = nowMs()
        if (!heardFromHost && now - lastPunchMs >= PUNCH_INTERVAL_MS) {
            lastPunchMs = now
            trySend(probe)
        }
        if (frameGate.isHolding) {
            val keyframes = reassembler.pending.filter { it.isKeyframe }.map { it.frameNo }.toSet()
            publish(frameGate.poll(now, keyframes))
        }
        val poll = nackTracker.poll(reassembler, now)
        if (poll.nacks.isNotEmpty()) trySend(MediaPacket.nack(streamId, poll.nacks))
        if (poll.abandoned.isNotEmpty()) listener.onKeyframeNeeded()
    }

    private fun maintain() = health.maintain(
        heardFromHost, sendProbe = { trySend(probe) },
        askResync = { resyncSink(ControlMessage.RekeyResync(cipher.receiveEpoch, true)) }, onLinkLost = listener::onLinkLost,
    )

    private fun trySend(packet: MediaPacket) {
        try { sendPacket(packet) } catch (e: TransportException) { /* mất gói probe/NACK là bình thường trên UDP; link-timeout lo phần còn lại */ }
    }

    override fun close() {
        if (closed) return
        closed = true
        selector.wakeup()
        if (::thread.isInitialized) thread.join(500)
        try { channel.close() } catch (e: IOException) { /* đã đóng */ }
        try { selector.close() } catch (e: IOException) { /* đã đóng */ }
    }

    companion object {
        const val PUNCH_INTERVAL_MS = 250L
        const val POLL_INTERVAL_MS = 10L
        const val LINK_TIMEOUT_MS = LinkHealth.LINK_TIMEOUT_MS
        private const val MAX_DATAGRAM = 2048

        fun monotonicMs(): Long = System.nanoTime() / 1_000_000

        /** Mở kênh tới `host:port` do `display.ready` báo. `threadFactory` cho phép app đặt ưu tiên thread (Android). */
        fun connect(
            streamId: Int,
            host: InetAddress,
            port: Int,
            keys: UdpKeys,
            listener: UdpMediaListener,
            resyncSink: (ControlMessage.RekeyResync) -> Unit,
            threadFactory: (Runnable) -> Thread = { Thread(it, "xdesk-udp") },
            nowMs: () -> Long = ::monotonicMs,
        ): UdpMediaChannel {
            val channel = try {
                DatagramChannel.open().apply { connect(InetSocketAddress(host, port)); configureBlocking(false) }
            } catch (e: IOException) {
                transportError(TransportErrorCode.CONNECTION_FAILED, e.message, e)
            }
            val media = UdpMediaChannel(streamId, channel, keys, listener, resyncSink, nowMs)
            media.channel.register(media.selector, java.nio.channels.SelectionKey.OP_READ)
            media.thread = threadFactory(media::runLoop).also { it.isDaemon = true; it.start() }
            return media
        }
    }
}
