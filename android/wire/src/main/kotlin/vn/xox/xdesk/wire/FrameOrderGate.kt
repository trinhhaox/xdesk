package vn.xox.xdesk.wire

/**
 * Cổng thứ tự frame đặt sau [Reassembler]: nhả frame cho decoder theo `frameNo` tăng dần.
 * Frame hoàn tất đúng thứ tự → nhả ngay (không thêm trễ). Frame đến trước khi frame đứng trước nó xong → giữ tối đa
 * [HOLD_BOUND_MS]. Hết hạn → bỏ frame thiếu: keyframe đã đủ thì nhảy tới đó (IDR không phụ thuộc gì phía trước);
 * không thì bỏ P-frame, nhả phần đang giữ và đòi keyframe. Nếu frame bỏ là IDR (đã thấy mảnh của nó) thì mọi P-frame
 * sau đó bị loại tới khi có keyframe mới. Thời gian do người gọi truyền (`nowMs`); chi phí theo số frame đang giữ
 * chứ không theo khoảng cách `frameNo`.
 */
class FrameOrderGate(firstFrameNo: Long = 0) {
    class Output(
        /** Frame nhả cho decoder, theo thứ tự. */
        val frames: List<AssembledFrame>,
        /** Mọi frame < giá trị này đã bị bỏ: người gọi báo cho [Reassembler.abandonBefore]. */
        val skipTo: Long?,
        /** Cần `keyframe.request` (đã bỏ frame hoặc đang loại P-frame chờ IDR). */
        val keyframeNeeded: Boolean,
    )

    private class Held(val frame: AssembledFrame, val arrivedMs: Long)

    private class Builder {
        val frames = ArrayList<AssembledFrame>()
        var skipTo: Long? = null
        var keyframeNeeded = false
        fun build() = Output(frames, skipTo, keyframeNeeded)
    }

    private val held = HashMap<Long, Held>()
    private var awaitingKeyframe = false

    /** Frame kế tiếp được phép nhả. */
    var nextFrameNo: Long = firstFrameNo
        private set
    var skippedGapCount = 0
        private set
    var droppedDependentCount = 0
        private set

    val isHolding: Boolean get() = held.isNotEmpty()

    fun push(frame: AssembledFrame, nowMs: Long): Output {
        val out = Builder()
        if (frame.frameNo < nextFrameNo || frame.frameNo in held) return out.build()
        if (frame.isKeyframe && frame.frameNo > nextFrameNo) {
            held.keys.removeAll { it < frame.frameNo }
            skip(frame.frameNo, out)
            awaitingKeyframe = false
        }
        if (frame.frameNo == nextFrameNo) {
            release(frame, out)
            drain(out)
            return out.build()
        }
        held[frame.frameNo] = Held(frame, nowMs)
        if (held.size > MAX_HELD) giveUp(out, emptySet())
        return out.build()
    }

    /** Gọi định kỳ: hết hạn chờ → bỏ frame thiếu. `pendingKeyframes` = frame đang ghép dở đã biết là keyframe. */
    fun poll(nowMs: Long, pendingKeyframes: Set<Long>): Output {
        val out = Builder()
        while (true) {
            val oldest = held.values.minOfOrNull { it.arrivedMs } ?: break
            if (nowMs - oldest < HOLD_BOUND_MS) break
            giveUp(out, pendingKeyframes)
        }
        return out.build()
    }

    private fun giveUp(out: Builder, pendingKeyframes: Set<Long>) {
        val lowest = held.keys.minOrNull() ?: return
        if (pendingKeyframes.any { it >= nextFrameNo && it < lowest }) awaitingKeyframe = true
        skip(lowest, out)
        out.keyframeNeeded = true
        drain(out)
    }

    private fun skip(frameNo: Long, out: Builder) {
        skippedGapCount++
        nextFrameNo = frameNo
        out.skipTo = frameNo
    }

    private fun drain(out: Builder) {
        while (true) release((held.remove(nextFrameNo) ?: break).frame, out)
    }

    private fun release(frame: AssembledFrame, out: Builder) {
        nextFrameNo = frame.frameNo + 1
        if (frame.isKeyframe) awaitingKeyframe = false
        if (awaitingKeyframe) {
            droppedDependentCount++
            out.keyframeNeeded = true
        } else {
            out.frames.add(frame)
        }
    }

    companion object {
        /** Thời gian giữ frame đã đủ để chờ frame đứng trước (≈ 1 RTT; NACK lần đầu sau 20 ms). */
        const val HOLD_BOUND_MS = 50L
        /** Số frame đang giữ tối đa; vượt → coi như hết hạn ngay. */
        const val MAX_HELD = 32
    }
}
