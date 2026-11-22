package vn.xox.xdesk.app

import vn.xox.xdesk.wire.MirrorFit

/** Kiểu Chiếu màn hình kế tiếp để đổi ngay trong phiên; null khi không ở chế độ Chiếu màn hình Mac hoặc chưa phát. */
fun ViewerController.nextFit(): MirrorFit? {
    if (!streaming || activeWorkMode != WorkMode.MIRROR) return null
    val fits = DisplaySettingsStore.SUPPORTED_FITS
    return fits[(fits.indexOf(display.fit) + 1) % fits.size]
}
