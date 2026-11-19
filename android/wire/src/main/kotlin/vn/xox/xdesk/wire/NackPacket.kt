package vn.xox.xdesk.wire

/** Mục NACK: mảnh `fragIdx` của `frameNo`; `WHOLE_FRAME` = chưa nhận mảnh nào. */
data class NackEntry(val frameNo: Long, val fragIdx: Int) {
    companion object {
        const val WHOLE_FRAME = 0xFFFF
        const val MAX_ENTRIES = 64
        internal const val ENTRY_SIZE = 6
    }
}

/** Payload gói nack: `u8 count (1…64) | count × (u32 frameNo | u16 fragIdx)`. */
object NackPayload {
    fun encode(entries: List<NackEntry>): ByteArray {
        if (entries.size !in 1..NackEntry.MAX_ENTRIES) wireError(WireErrorCode.invalidNackCount, "${entries.size}")
        val w = ByteWriter(1 + entries.size * NackEntry.ENTRY_SIZE)
        w.u8(entries.size)
        for (e in entries) { w.u32(e.frameNo); w.u16(e.fragIdx) }
        return w.toByteArray()
    }

    fun decode(payload: ByteArray): List<NackEntry> {
        val r = ByteReader(payload)
        val count = r.u8()
        if (count !in 1..NackEntry.MAX_ENTRIES) wireError(WireErrorCode.invalidNackCount, "$count")
        if (r.remaining != count * NackEntry.ENTRY_SIZE) {
            wireError(WireErrorCode.truncated, "need ${count * NackEntry.ENTRY_SIZE}, have ${r.remaining}")
        }
        return List(count) { NackEntry(r.u32(), r.u16()) }
    }
}
