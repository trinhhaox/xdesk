package vn.xox.xdesk.app

import vn.xox.xdesk.transport.ViewerAuth
import vn.xox.xdesk.transport.ViewerTarget
import vn.xox.xdesk.wire.MirrorFit

/**
 * Vùng hiển thị thật (px, sau khi trừ tai thỏ) do màn stream báo. Khác vùng đã xin thì mở lại phiên với đúng cỡ này,
 * để video không bị kéo giãn/cắt; riêng Giống màn hình Mac không đàm phán lại ([ViewportPolicy]).
 */
fun ViewerController.onViewportChanged(width: Int, height: Int) {
    viewport.actual = width to height
    checkViewport()
}

fun ViewerController.clearViewport() { viewport.actual = null }

/** Đổi kiểu Bản sao rồi kết nối lại (host phải đổi cỡ màn hình nên phải đàm phán lại). */
fun ViewerController.switchFit(next: MirrorFit) {
    val target = session?.connectedTarget ?: lastTarget ?: return
    container.display.selectFit(next)
    restartWith(target)
}

internal fun ViewerController.restartWith(target: ViewerTarget) {
    val ending = session ?: return
    endSession()
    background.execute { ending.disconnect() }
    decoder.stop()
    start(listOf(target), ViewerAuth.Automatic)
}
