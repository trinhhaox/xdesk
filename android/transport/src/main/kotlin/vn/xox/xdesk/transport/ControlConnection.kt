package vn.xox.xdesk.transport

import java.io.Closeable
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.atomic.AtomicBoolean
import vn.xox.xdesk.crypto.HandshakeFrame
import vn.xox.xdesk.crypto.SessionKeys
import vn.xox.xdesk.crypto.StreamFormat
import vn.xox.xdesk.crypto.StreamReceiver
import vn.xox.xdesk.crypto.StreamSender
import vn.xox.xdesk.wire.ControlEnvelope
import vn.xox.xdesk.wire.ControlFrame
import vn.xox.xdesk.wire.ControlFrameCodec
import vn.xox.xdesk.wire.ControlFrameDecoder
import vn.xox.xdesk.wire.ControlFrameKind
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.ControlMessageCodec

/**
 * Kênh điều khiển TCP phía viewer (blocking, thread-safe cho phần gửi).
 * Trước [installSession] chỉ đi frame bắt tay (kind 0x01); sau đó mọi frame 0x02-0x04 đi qua StreamSender/Receiver.
 * Chỉ MỘT thread được gọi [nextInbound]/[receiveHandshake] tại một thời điểm.
 */
class ControlConnection private constructor(private val socket: Socket, private val nowMs: () -> Long) : Closeable {
    private val closedFlag = AtomicBoolean(false)
    private val writeLock = Any()
    private val decoder = ControlFrameDecoder()
    private val readBuffer = ByteArray(READ_CHUNK)
    private var nextMessageId = 1L
    private var sender: StreamSender? = null
    private var receiver: StreamReceiver? = null
    private var framesSinceRekey = 0L
    private var sendEpochStartMs = 0L

    /** Chu kỳ rekey chiều gửi; để public cho test rút ngắn. */
    var rekeyIntervalMs = REKEY_INTERVAL_MS

    /** Khoá UDP dẫn xuất từ phiên Noise (null trước khi bắt tay xong). */
    @Volatile var udpKeys: UdpKeys? = null
        private set

    val isClosed: Boolean get() = closedFlag.get()
    val isSecured: Boolean get() = sender != null

    /** Địa chỉ IP thực của host (dùng để mở UDP tới cùng máy). */
    val remoteAddress: java.net.InetAddress get() = socket.inetAddress

    /** Hạn chờ một lần đọc (0 = vô hạn). Quá hạn → [TransportErrorCode.TIMED_OUT]. */
    fun setReadTimeout(ms: Int) { socket.soTimeout = ms }

    // MARK: Gửi

    /** Gửi một message điều khiển; trả `id` đã dùng (tự tăng nếu không truyền; phản hồi truyền lại `id` của yêu cầu). */
    fun send(message: ControlMessage, id: Long? = null): Long {
        val useId = id ?: synchronized(writeLock) { nextMessageId++ }
        sendFrame(ControlFrame(ControlFrameKind.CONTROL, ControlMessageCodec.encode(ControlEnvelope(useId, message))))
        return useId
    }

    fun sendHandshake(frame: HandshakeFrame) {
        sendFrame(ControlFrame(ControlFrameKind.HANDSHAKE, frame.encode()))
    }

    private fun sendFrame(frame: ControlFrame) {
        if (isClosed) transportError(TransportErrorCode.CONNECTION_CLOSED)
        synchronized(writeLock) {
            try {
                socket.getOutputStream().apply { write(wireBytes(frame)); flush() }
            } catch (e: IOException) {
                close()
                transportError(TransportErrorCode.CONNECTION_FAILED, e.message, e)
            }
        }
    }

    /** Seal (nếu đã mã hoá) và chèn `rekey` khi tới hạn, trong khoá ghi để thứ tự nonce = thứ tự byte trên dây. */
    private fun wireBytes(frame: ControlFrame): ByteArray {
        val box = sender ?: run {
            if (frame.kind != ControlFrameKind.HANDSHAKE) transportError(TransportErrorCode.PROTOCOL_VIOLATION, "chưa xác thực")
            return ControlFrameCodec.encode(frame)
        }
        if (frame.kind == ControlFrameKind.HANDSHAKE) transportError(TransportErrorCode.PROTOCOL_VIOLATION, "frame bắt tay sau khi đã mã hoá")
        var out = ByteArray(0)
        if (framesSinceRekey >= REKEY_FRAME_THRESHOLD || nowMs() - sendEpochStartMs >= rekeyIntervalMs) {
            val rekey = ControlMessageCodec.encode(ControlEnvelope(0, ControlMessage.Rekey))
            out = sealed(box, ControlFrame(ControlFrameKind.CONTROL, rekey))
            box.rekey()
            framesSinceRekey = 0
            sendEpochStartMs = nowMs()
        }
        return out + sealed(box, frame)
    }

    private fun sealed(box: StreamSender, frame: ControlFrame): ByteArray {
        val ciphertext = box.seal(frame.kind.raw, frame.payload)
        framesSinceRekey++
        val len = 1 + ciphertext.size
        val head = byteArrayOf((len ushr 24).toByte(), (len ushr 16).toByte(), (len ushr 8).toByte(), len.toByte(), frame.kind.raw.toByte())
        return head + ciphertext
    }

    /** Chuyển sang kênh mã hoá sau message cuối của Noise. */
    fun installSession(keys: SessionKeys) {
        synchronized(writeLock) {
            sender = StreamSender(keys.tcpSend)
            sendEpochStartMs = nowMs()
        }
        receiver = StreamReceiver(keys.tcpReceive)
        decoder.extraBulkAllowance = StreamFormat.TAG_LENGTH
        udpKeys = UdpKeys(keys.udpSend, keys.udpReceive)
    }

    // MARK: Nhận

    /** Đọc đúng một frame bắt tay. Đóng kết nối nếu lỗi. */
    fun receiveHandshake(): HandshakeFrame {
        val frame = guarded { nextRawFrame() ?: transportError(TransportErrorCode.CONNECTION_CLOSED) }
        if (frame.kind != ControlFrameKind.HANDSHAKE) {
            close()
            transportError(TransportErrorCode.PROTOCOL_VIOLATION, "cần frame bắt tay")
        }
        return guarded { HandshakeFrame.decode(frame.payload) }
    }

    /** Chờ thứ kế tiếp; `null` khi host đóng sạch. `t` lạ bị bỏ qua; `rekey` xử lý nội bộ. */
    fun nextInbound(): ControlInbound? {
        while (true) {
            val raw = guarded { nextRawFrame() } ?: run { close(); return null }
            val box = receiver
            if (box == null || raw.kind == ControlFrameKind.HANDSHAKE) {
                close()
                transportError(TransportErrorCode.PROTOCOL_VIOLATION, "frame ${raw.kind} không hợp lệ ở trạng thái này")
            }
            val inbound = guarded { decodeInbound(box, raw) }
            if (inbound != null) return inbound
        }
    }

    private fun nextRawFrame(): ControlFrame? {
        while (true) {
            decoder.next()?.let { return it }
            val n = try {
                socket.getInputStream().read(readBuffer)
            } catch (e: SocketTimeoutException) {
                transportError(TransportErrorCode.TIMED_OUT, cause = e)
            } catch (e: IOException) {
                if (isClosed) return null
                transportError(TransportErrorCode.CONNECTION_FAILED, e.message, e)
            }
            if (n < 0) return null
            decoder.append(readBuffer.copyOf(n))
        }
    }

    /** Lỗi giải khung/giải mã/JSON → đóng kết nối rồi ném tiếp. */
    private inline fun <T> guarded(block: () -> T): T = try {
        block()
    } catch (e: Exception) {
        close()
        throw e
    }

    /** Idempotent. */
    override fun close() {
        if (closedFlag.compareAndSet(false, true)) {
            try { socket.close() } catch (e: IOException) { /* socket đã hỏng: không còn gì để giải phóng */ }
        }
    }

    companion object {
        const val REKEY_INTERVAL_MS = 3_600_000L
        const val REKEY_FRAME_THRESHOLD = 1L shl 32
        private const val READ_CHUNK = 64 * 1024

        fun connect(host: String, port: Int, timeoutMs: Int = 5000, nowMs: () -> Long = System::currentTimeMillis): ControlConnection {
            val socket = Socket()
            try {
                socket.tcpNoDelay = true
                socket.connect(InetSocketAddress(host, port), timeoutMs)
            } catch (e: IOException) {
                try { socket.close() } catch (ignored: IOException) { /* chưa mở được */ }
                transportError(TransportErrorCode.CONNECTION_FAILED, e.message, e)
            }
            return ControlConnection(socket, nowMs)
        }
    }
}
