package vn.xox.xdesk.app

import vn.xox.xdesk.wire.MirrorFit
import vn.xox.xdesk.wire.ScreenMode

/** Kiểu Bản sao kế tiếp để đổi ngay trong phiên; null khi không phải Bản sao hoặc chưa phát. */
fun ViewerController.nextFit(): MirrorFit? {
    if (!streaming || display.mode != ScreenMode.MIRROR) return null
    val fits = DisplaySettingsStore.SUPPORTED_FITS
    return fits[(fits.indexOf(display.fit) + 1) % fits.size]
}
