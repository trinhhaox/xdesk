package vn.xox.xdesk.transport

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Mã 6 số phía viewer. UI hiện [code] rồi gọi [answer] khi người dùng so với mã trên host.
 *
 * Ghép đôi SAS chỉ an toàn khi cả hai phía cùng xác nhận: host bấm "Khớp" chưa đủ, vì một máy mạo danh
 * host trên LAN có thể tự trả `pair.result{accepted:true}`. Viewer chỉ lưu host sau khi chính người dùng
 * ở viewer bấm "Khớp".
 */
class SasPrompt internal constructor(val code: String, private val onMismatch: () -> Unit = {}) {
    private val result = AtomicReference<Boolean?>(null)
    private val latch = CountDownLatch(1)

    /** `true` = mã khớp với host; `false` = không khớp (huỷ ghép đôi ngay). Chỉ lần trả lời đầu có hiệu lực. */
    fun answer(matched: Boolean) {
        if (resolve(matched) && !matched) onMismatch()
    }

    /** Câu trả lời đã có (null = chưa trả lời). */
    internal val answered: Boolean? get() = result.get()

    /** Còn chờ người dùng trả lời; ghép đôi đã kết thúc thì UI không hiện lại prompt này. */
    val isPending: Boolean get() = result.get() == null

    /** Ghép đôi kết thúc giữa chừng (host từ chối, mất kết nối): coi như không khớp, không gọi hook đóng kết nối. */
    internal fun abandon() {
        resolve(false)
    }

    /** Chặn tới khi người dùng trả lời; quá hạn hoặc luồng bị ngắt thì coi là không khớp. */
    internal fun awaitDecision(timeoutMs: Long): Boolean {
        try {
            if (!latch.await(timeoutMs, TimeUnit.MILLISECONDS)) resolve(false)
        } catch (e: InterruptedException) {
            resolve(false)
            Thread.currentThread().interrupt()
        }
        return result.get() == true
    }

    private fun resolve(matched: Boolean): Boolean {
        if (!result.compareAndSet(null, matched)) return false
        latch.countDown()
        return true
    }
}
