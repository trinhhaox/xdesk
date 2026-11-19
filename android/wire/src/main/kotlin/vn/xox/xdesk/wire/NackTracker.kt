package vn.xox.xdesk.wire

/** Quyết định khi nào gửi NACK / bỏ frame. Không giữ đồng hồ; người gọi truyền `nowMs`. */
class NackTracker(val config: Config = Config()) {
    class Config(
        /** Chờ trước khi NACK lần đầu (≈ RTT/2). */
        val nackDelayMs: Long = 20,
        /** Khoảng cách tối thiểu giữa hai lần NACK cùng một mảnh. */
        val retryIntervalMs: Long = 40,
        /** Quá hạn này → bỏ frame; người gọi nên gửi `keyframe.request`. */
        val giveUpMs: Long = 500,
    )

    class Poll(val nacks: List<NackEntry>, val abandoned: List<Long>)

    private class Candidate(val frameNo: Long, val firstSeenMs: Long, val missing: List<Int>)

    private val gapSince = HashMap<Long, Long>()
    private val lastSent = HashMap<NackEntry, Long>()

    fun poll(reassembler: Reassembler, nowMs: Long): Poll {
        val candidates = ArrayList<Candidate>()
        for (frameNo in reassembler.gaps) {
            candidates += Candidate(frameNo, gapSince[frameNo] ?: nowMs, listOf(NackEntry.WHOLE_FRAME))
        }
        for (p in reassembler.pending) candidates += Candidate(p.frameNo, p.firstSeenMs, p.missing)
        candidates.sortBy { it.frameNo }

        val nacks = ArrayList<NackEntry>()
        val abandoned = ArrayList<Long>()
        for (c in candidates) {
            gapSince[c.frameNo] = c.firstSeenMs
            val age = nowMs - c.firstSeenMs
            if (age >= config.giveUpMs) {
                reassembler.abandon(c.frameNo)
                abandoned += c.frameNo
                continue
            }
            if (age < config.nackDelayMs) continue
            for (idx in c.missing) {
                if (nacks.size >= NackEntry.MAX_ENTRIES) break
                val entry = NackEntry(c.frameNo, idx)
                val last = lastSent[entry]
                if (last != null && nowMs - last < config.retryIntervalMs) continue
                lastSent[entry] = nowMs
                nacks += entry
            }
        }
        val watermark = reassembler.watermark
        gapSince.keys.removeAll { it < watermark }
        lastSent.keys.removeAll { it.frameNo < watermark }
        return Poll(nacks, abandoned)
    }
}
