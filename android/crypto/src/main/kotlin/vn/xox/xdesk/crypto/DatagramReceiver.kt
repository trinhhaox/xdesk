package vn.xox.xdesk.crypto

class OpenedDatagram(val header: ByteArray, val payload: ByteArray)

/**
 * Phía nhận UDP: kiểm replay (cửa sổ 1024), xác thực AEAD rồi mới cập nhật trạng thái. Chấp nhận epoch hiện tại,
 * epoch ngay trước, và nhảy tới [MAX_EPOCH_LOOKAHEAD] epoch mới hơn (khoá dẫn xuất thử; chỉ chuyển epoch khi tag đúng).
 * Xa hơn → `unknownEpoch`; phục hồi bằng [resync] qua control `rekey.resync`. Không thread-safe.
 */
class DatagramReceiver(key: ByteArray) {
    private class Epoch(val number: Long, val key: ByteArray) {
        val window = ReplayWindow()
    }

    private var current = Epoch(0, key.copyOf())
    private var previous: Epoch? = null

    val epoch: Long get() = current.number

    /** Kéo khoá nhận lên `target`; chỉ gọi với epoch báo qua kênh control đã xác thực. Chênh > 64 bị từ chối. */
    fun resync(toEpoch: Long) {
        if (toEpoch <= current.number) return
        if (toEpoch - current.number > MAX_RESYNC_GAP) cryptoError(CryptoErrorCode.unknownEpoch)
        previous = null
        current = Epoch(toEpoch, advance(current.key, toEpoch - current.number))
    }

    fun open(datagram: ByteArray): OpenedDatagram {
        val bodyStart = DatagramFormat.HEADER_LENGTH + DatagramFormat.NONCE_LENGTH
        if (datagram.size < bodyStart + DatagramFormat.TAG_LENGTH) cryptoError(CryptoErrorCode.datagramTooShort)
        var nonce = 0L
        for (i in DatagramFormat.HEADER_LENGTH until bodyStart) nonce = (nonce shl 8) or (datagram[i].toLong() and 0xFF)
        val counter = nonce and 0xFFFFFFFFL

        val slot = trialEpoch(nonce ushr 32)
        when (slot.window.verdict(counter)) {
            ReplayWindow.Verdict.FRESH -> Unit
            ReplayWindow.Verdict.DUPLICATE -> cryptoError(CryptoErrorCode.replayed)
            ReplayWindow.Verdict.TOO_OLD -> cryptoError(CryptoErrorCode.outsideReplayWindow)
        }
        val header = datagram.copyOfRange(0, DatagramFormat.HEADER_LENGTH)
        val payload = Primitives.open(slot.key, nonce, header, datagram.copyOfRange(bodyStart, datagram.size))
        slot.window.accept(counter)
        commit(slot)
        return OpenedDatagram(header, payload)
    }

    /** Epoch dùng để thử giải mã; chưa đổi gì ở `this`. */
    private fun trialEpoch(number: Long): Epoch {
        if (number == current.number) return current
        if (number > current.number && number - current.number <= MAX_EPOCH_LOOKAHEAD) {
            return Epoch(number, advance(current.key, number - current.number))
        }
        previous?.let { if (it.number == number) return it }
        cryptoError(CryptoErrorCode.unknownEpoch)
    }

    /** Chỉ gọi sau khi tag đã xác thực. */
    private fun commit(slot: Epoch) {
        if (slot.number > current.number) {
            // Giữ epoch ngay trước epoch mới cho gói đến muộn: liền kề thì giữ nguyên, nếu không dẫn xuất lại (cửa sổ mới).
            previous = if (slot.number - current.number == 1L) current
            else Epoch(slot.number - 1, advance(current.key, slot.number - 1 - current.number))
            current = slot
        } else if (slot.number < current.number) {
            previous = slot
        }
    }

    private fun advance(key: ByteArray, steps: Long): ByteArray {
        var k = key
        repeat(steps.toInt()) { k = KeySchedule.next(k) }
        return k
    }

    companion object {
        const val MAX_EPOCH_LOOKAHEAD = 4L
        const val MAX_RESYNC_GAP = 64L
    }
}
