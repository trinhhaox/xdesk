package vn.xox.xdesk.app

import android.os.Handler

/** Nhớ vùng hiển thị đã xin host và vùng thật màn stream báo; khi lệch (theo [ViewportPolicy]) thì hẹn mở lại phiên sau khi ổn định. */
internal class ViewportTracker(private val main: Handler) {
    var requested: Pair<Int, Int>? = null
    var actual: Pair<Int, Int>? = null
    private var pending = Runnable { }

    fun schedule(streaming: Boolean, native: Boolean, restart: () -> Unit) {
        main.removeCallbacks(pending)
        val want = requested ?: return
        val have = actual ?: return
        if (!streaming || !ViewportPolicy.needsRenegotiation(native, want, have)) return
        pending = Runnable(restart)
        main.postDelayed(pending, SETTLE_MS)
    }

    /** Huỷ lần mở lại phiên đang hẹn (ngắt kết nối/đóng màn): không để nó chạy sau khi phiên đã kết thúc. */
    fun cancel() = main.removeCallbacks(pending)

    private companion object { const val SETTLE_MS = 600L }
}
