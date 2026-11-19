package vn.xox.xdesk.crypto

/** Cửa sổ chống phát lại 1024 gói (bitmap vòng) cho bộ đếm nonce UDP trong một epoch. */
internal class ReplayWindow {
    enum class Verdict { FRESH, DUPLICATE, TOO_OLD }

    private var highest: Long? = null
    private val bits = LongArray((SIZE / 64).toInt())

    /** Không đổi trạng thái; chỉ gọi [accept] sau khi gói đã xác thực AEAD. */
    fun verdict(counter: Long): Verdict {
        val top = highest
        if (top == null || counter > top) return Verdict.FRESH
        if (top - counter >= SIZE) return Verdict.TOO_OLD
        return if (isSet(counter)) Verdict.DUPLICATE else Verdict.FRESH
    }

    fun accept(counter: Long) {
        val top = highest
        if (top == null) {
            highest = counter
        } else if (counter > top) {
            val advance = counter - top
            if (advance >= SIZE) bits.fill(0) else for (step in 1..advance) clear(top + step)
            highest = counter
        }
        val slot = (counter % SIZE).toInt()
        bits[slot / 64] = bits[slot / 64] or (1L shl (slot % 64))
    }

    private fun isSet(counter: Long): Boolean {
        val slot = (counter % SIZE).toInt()
        return bits[slot / 64] and (1L shl (slot % 64)) != 0L
    }

    private fun clear(counter: Long) {
        val slot = (counter % SIZE).toInt()
        bits[slot / 64] = bits[slot / 64] and (1L shl (slot % 64)).inv()
    }

    companion object { const val SIZE = 1024L }
}
