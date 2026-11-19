package vn.xox.xdesk.wire

class AssembledFrame(
    val streamId: Int,
    val frameNo: Long,
    val ptsMs: Long,
    val isKeyframe: Boolean,
    val data: ByteArray,
)

/** Frame đang ghép dở: các mảnh còn thiếu để gửi NACK. */
data class PendingFrame(val frameNo: Long, val missing: List<Int>, val firstSeenMs: Long)

/**
 * Ghép mảnh theo `frameNo`; chịu mất gói, đảo thứ tự, trùng lặp. Thời gian do người gọi truyền (`nowMs`).
 * `frameNo` coi như không quay vòng trong một phiên. Mọi thao tác tốn theo số frame đang giữ (≤ [WINDOW]),
 * không theo khoảng cách nhảy của `frameNo` (gói hỏng có frameNo khổng lồ không được làm treo bộ ghép).
 */
class Reassembler(firstFrameNo: Long = 0, private val maxPendingBytes: Int = 32 shl 20) {
    private class Partial(
        val parts: Array<ByteArray?>,
        val isKeyframe: Boolean,
        val ptsMs: Long,
        val firstSeenMs: Long,
    ) {
        var received = 0
        var bytes = 0
    }

    private val partials = HashMap<Long, Partial>()
    /** Frame ≥ watermark đã hoàn tất hoặc đã bỏ (chặn gói trùng đến muộn). */
    private val finished = HashSet<Long>()
    private var highest: Long? = null
    private var pendingBytes = 0

    /** Mọi frame < watermark đã xong (hoặc bị bỏ); gói thuộc chúng bị bỏ qua. */
    var watermark: Long = firstFrameNo
        private set
    var abandonedCount = 0
        private set

    /** Frame nằm dưới frame mới nhất nhưng chưa nhận mảnh nào. */
    val gaps: List<Long>
        get() {
            val top = highest ?: return emptyList()
            if (top <= watermark) return emptyList()
            return (watermark until top).filter { it !in partials && it !in finished }
        }

    val pending: List<PendingFrame>
        get() = partials.keys.sorted().map { frameNo ->
            val p = partials.getValue(frameNo)
            PendingFrame(frameNo, p.parts.indices.filter { p.parts[it] == null }, p.firstSeenMs)
        }

    /** Nhận một gói; trả frame khi vừa đủ mảnh. Gói trùng/cũ → `null`; gói sai → [WireException]. */
    fun ingest(packet: MediaPacket, nowMs: Long): AssembledFrame? {
        val h = packet.header
        if (h.type != MediaPacketType.VIDEO && h.type != MediaPacketType.AUDIO) {
            wireError(WireErrorCode.unexpectedPacketType, "${h.type.raw}")
        }
        h.validate()
        if (packet.payload.isEmpty()) wireError(WireErrorCode.emptyPayload)
        if (packet.payload.size > MediaPacket.MAX_PAYLOAD) wireError(WireErrorCode.payloadTooLarge, "${packet.payload.size}")
        if (h.frameNo < watermark || h.frameNo in finished) return null

        val partial = partials[h.frameNo] ?: Partial(arrayOfNulls(h.fragCnt), h.isKeyframe, h.ptsMs, nowMs)
        if (partial.parts.size != h.fragCnt) wireError(WireErrorCode.inconsistentFragmentCount, "frame ${h.frameNo}")
        highest = maxOf(highest ?: h.frameNo, h.frameNo)
        if (partial.parts[h.fragIdx] != null) return null

        partial.parts[h.fragIdx] = packet.payload
        partial.received++
        partial.bytes += packet.payload.size
        pendingBytes += packet.payload.size

        if (partial.received == partial.parts.size) {
            partials.remove(h.frameNo)
            pendingBytes -= partial.bytes
            markFinished(h.frameNo)
            enforceLimits()
            val out = ByteArray(partial.bytes)
            var offset = 0
            for (part in partial.parts) {
                val bytes = part ?: continue
                bytes.copyInto(out, offset)
                offset += bytes.size
            }
            return AssembledFrame(h.streamId, h.frameNo, partial.ptsMs, partial.isKeyframe, out)
        }
        partials[h.frameNo] = partial
        enforceLimits()
        return null
    }

    /** Bỏ một frame (quá hạn): coi như đã xong để watermark tiến lên. */
    fun abandon(frameNo: Long) {
        if (frameNo < watermark || frameNo in finished) return
        partials.remove(frameNo)?.let { pendingBytes -= it.bytes }
        abandonedCount++
        markFinished(frameNo)
    }

    private fun advanceWatermark(newWatermark: Long) {
        val dropped = partials.keys.filter { it < newWatermark }
        for (frameNo in dropped) partials.remove(frameNo)?.let { pendingBytes -= it.bytes }
        val finishedBelow = finished.count { it < newWatermark }
        abandonedCount += (newWatermark - watermark - finishedBelow).toInt()
        finished.removeAll { it < newWatermark }
        watermark = newWatermark
        while (finished.remove(watermark)) watermark++
    }

    private fun markFinished(frameNo: Long) {
        finished.add(frameNo)
        while (finished.remove(watermark)) watermark++
    }

    private fun enforceLimits() {
        val top = highest
        if (top != null && top >= watermark && top - watermark >= WINDOW) advanceWatermark(top - WINDOW + 1)
        while (pendingBytes > maxPendingBytes) {
            val oldest = partials.keys.minOrNull() ?: break
            abandon(oldest)
        }
    }

    companion object {
        /** Số frame tối đa giữa watermark và frame mới nhất; vượt → bỏ frame cũ nhất. */
        const val WINDOW = 256L
    }
}
