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

/** Chuẩn bị chế độ làm việc trước khi kết nối (mặc định theo Cài đặt hoặc ép một chế độ khác). */
fun ViewerController.prepareForConnect(overrideMode: WorkMode? = null) {
    val targetMode = overrideMode ?: container.display.defaultWorkMode
    activeWorkMode = targetMode
    targetMode.screenMode?.let { container.display.selectMode(it) }
}

/** Đổi chế độ làm việc ngay trong khi đang kết nối Mac (nếu đổi giữa Chiếu Mac ↔ Màn phụ thì thương lượng lại `display.config`). */
fun ViewerController.switchWorkMode(next: WorkMode) {
    if (activeWorkMode == next) return
    val currentScreen = negotiatedScreenMode ?: container.display.mode
    activeWorkMode = next
    val neededScreen = next.screenMode ?: return
    if (neededScreen != currentScreen) {
        container.display.selectMode(neededScreen)
        val target = session?.connectedTarget ?: lastTarget ?: return
        restartWith(target)
    }
}

/** Đổi kiểu Chiếu màn hình rồi kết nối lại (host phải đổi cỡ màn hình nên phải đàm phán lại). */
fun ViewerController.switchFit(next: MirrorFit) {
    if (container.display.fit == next) return
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
