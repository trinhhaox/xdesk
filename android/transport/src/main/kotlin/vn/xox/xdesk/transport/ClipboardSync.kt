package vn.xox.xdesk.transport

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import vn.xox.xdesk.wire.ClipKind
import vn.xox.xdesk.wire.ClipLimits
import vn.xox.xdesk.wire.ControlMessage

/** Một mục clipboard đã chuẩn hoá: văn bản UTF-8 hợp lệ hoặc ảnh PNG (≤ 10 MiB). */
class ClipboardItem private constructor(
    val kind: ClipKind,
    val data: ByteArray,
    val hash: String,
) {
    val size: Long get() = data.size.toLong()
    val text: String? get() = if (kind == ClipKind.TEXT) String(data, Charsets.UTF_8) else null

    override fun equals(other: Any?): Boolean =
        other is ClipboardItem && kind == other.kind && hash == other.hash && data.contentEquals(other.data)

    override fun hashCode(): Int = 31 * (31 * kind.hashCode() + hash.hashCode()) + data.contentHashCode()

    companion object {
        private val PNG_SIGNATURE = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)

        fun of(kind: ClipKind, data: ByteArray): ClipboardItem? {
            if (data.isEmpty() || data.size > ClipLimits.MAX_BYTES) return null
            if (!isWellFormed(kind, data)) return null
            return ClipboardItem(kind, data, sha256Hex(data))
        }

        fun text(text: String): ClipboardItem? = of(ClipKind.TEXT, text.toByteArray(Charsets.UTF_8))

        internal fun sha256Hex(data: ByteArray): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(data)
            val hex = StringBuilder(digest.size * 2)
            for (b in digest) {
                val v = b.toInt() and 0xFF
                hex.append(HEX_CHARS[v ushr 4])
                hex.append(HEX_CHARS[v and 0x0F])
            }
            return hex.toString()
        }

        private val HEX_CHARS = "0123456789abcdef".toCharArray()

        private fun isWellFormed(kind: ClipKind, data: ByteArray): Boolean = when (kind) {
            ClipKind.TEXT -> try {
                Charsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(data))
                true
            } catch (_: CharacterCodingException) {
                false
            }
            ClipKind.IMAGE -> data.size >= PNG_SIGNATURE.size &&
                PNG_SIGNATURE.indices.all { i -> data[i] == PNG_SIGNATURE[i] }
        }
    }
}

/** Giao diện đọc/ghi clipboard hệ thống. */
interface ClipboardAccess {
    fun read(): ClipboardItem?
    fun write(item: ClipboardItem)
}

/** Kênh gửi clipboard qua TCP điều khiển. */
interface ClipboardTransport {
    fun sendClip(message: ControlMessage)
    fun sendClipData(header: ControlMessage.ClipData, payload: ByteArray)
}

/** Kết quả khi người dùng bấm "Gửi clipboard sang Mac". */
sealed interface ClipboardSendOutcome {
    data class Sent(val kind: ClipKind) : ClipboardSendOutcome
    data object Disabled : ClipboardSendOutcome
    data object NothingToSend : ClipboardSendOutcome
    data class Failed(val reason: String) : ClipboardSendOutcome
}

internal class ClipboardReceiver {
    enum class Failure { UNEXPECTED_CHUNK, SIZE_EXCEEDED, HASH_MISMATCH, MALFORMED_ITEM }
    class ReceiverException(val failure: Failure) : Exception(failure.name)

    private var header: ControlMessage.ClipData? = null
    private val buffer = ByteArrayOutputStream()

    val isReceiving: Boolean get() = header != null

    fun begin(header: ControlMessage.ClipData) {
        this.header = header
        buffer.reset()
    }

    fun reset() {
        header = null
        buffer.reset()
    }

    fun append(chunk: ByteArray): ClipboardItem? {
        val currentHeader = header ?: throw ReceiverException(Failure.UNEXPECTED_CHUNK)
        val expected = currentHeader.size.toInt()
        if (buffer.size() + chunk.size > expected) {
            reset()
            throw ReceiverException(Failure.SIZE_EXCEEDED)
        }
        buffer.write(chunk)
        if (buffer.size() < expected) return null
        val bytes = buffer.toByteArray()
        reset()
        val item = ClipboardItem.of(currentHeader.kind, bytes) ?: throw ReceiverException(Failure.MALFORMED_ITEM)
        if (item.hash != currentHeader.hash) throw ReceiverException(Failure.HASH_MISMATCH)
        return item
    }
}

/**
 * Đồng bộ clipboard hai chiều qua kênh control đã mã hoá:
 * `clip.offer {kind,size,hash}` -> `clip.pull {kind}` -> `clip.data {kind,size,hash}` + chunk `BULK`.
 * Chống lặp bằng SHA-256 + cửa sổ echo mặc định 3 giây.
 */
class ClipboardSync(
    private val transport: ClipboardTransport,
    private val clipboard: ClipboardAccess,
    private val echoWindowMs: Long = DEFAULT_ECHO_WINDOW_MS,
    private val nowMs: () -> Long = System::currentTimeMillis,
    private val isEnabled: () -> Boolean = { true },
) {
    private val lock = Any()
    private val offered = HashMap<ClipKind, ClipboardItem>()
    private val receiver = ClipboardReceiver()
    private var recentRemoteHash: String? = null
    private var recentRemoteAtMs: Long = 0L

    fun sendCurrent(): ClipboardSendOutcome {
        if (!isEnabled()) return ClipboardSendOutcome.Disabled
        val item = clipboard.read() ?: return ClipboardSendOutcome.NothingToSend
        return offer(item)
    }

    private fun offer(item: ClipboardItem): ClipboardSendOutcome {
        synchronized(lock) { offered[item.kind] = item }
        return try {
            transport.sendClip(ControlMessage.ClipOffer(item.kind, item.size, item.hash))
            ClipboardSendOutcome.Sent(item.kind)
        } catch (e: Exception) {
            ClipboardSendOutcome.Failed(e.message ?: "Lỗi kết nối")
        }
    }

    fun handle(message: ControlMessage) {
        if (message !is ControlMessage.ClipOffer &&
            message !is ControlMessage.ClipPull &&
            message !is ControlMessage.ClipData
        ) {
            return
        }
        if (!isEnabled()) return
        when (message) {
            is ControlMessage.ClipOffer -> pullIfWanted(message)
            is ControlMessage.ClipPull -> send(message.kind)
            is ControlMessage.ClipData -> synchronized(lock) { receiver.begin(message) }
            else -> Unit
        }
    }

    fun handleBulk(chunk: ByteArray) {
        val completed = synchronized(lock) {
            if (!receiver.isReceiving) return
            if (!isEnabled()) {
                receiver.reset()
                return
            }
            try {
                receiver.append(chunk)
            } catch (_: ClipboardReceiver.ReceiverException) {
                receiver.reset()
                null
            }
        } ?: return
        clipboard.write(completed)
        synchronized(lock) {
            recentRemoteHash = completed.hash
            recentRemoteAtMs = nowMs()
        }
    }

    fun reset() {
        synchronized(lock) {
            receiver.reset()
            offered.clear()
            recentRemoteHash = null
            recentRemoteAtMs = 0L
        }
    }

    private fun pullIfWanted(offer: ControlMessage.ClipOffer) {
        val hash = offer.hash
        if (hash != null && isRecentRemote(hash)) return
        try {
            transport.sendClip(ControlMessage.ClipPull(offer.kind))
        } catch (_: Exception) {
            // Kênh đã đóng: reader sẽ kết thúc phiên.
        }
    }

    private fun send(kind: ClipKind) {
        val item = synchronized(lock) { offered[kind] } ?: return
        try {
            transport.sendClipData(ControlMessage.ClipData(kind, item.size, item.hash), item.data)
        } catch (_: Exception) {
            // Kênh đã đóng: reader sẽ kết thúc phiên.
        }
    }

    private fun isRecentRemote(hash: String): Boolean = synchronized(lock) {
        val recent = recentRemoteHash ?: return@synchronized false
        recent == hash && (nowMs() - recentRemoteAtMs) < echoWindowMs
    }

    companion object {
        const val DEFAULT_ECHO_WINDOW_MS = 3_000L
    }
}
