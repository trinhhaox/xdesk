package vn.xox.xdesk.app

import vn.xox.xdesk.crypto.CryptoException
import vn.xox.xdesk.crypto.PairingURI
import vn.xox.xdesk.transport.ViewerAuth
import vn.xox.xdesk.transport.ViewerTarget

fun ViewerController.connectManual(text: String) {
    val target = ViewerTarget.parse(text) ?: return run { failure = ConnectionFailure("Địa chỉ phải có dạng host:port", false) }
    start(listOf(target), ViewerAuth.Automatic)
}

/** Thử lại kết nối tới host vừa lỗi (cùng cách xác thực tự động). */
fun ViewerController.retry() { lastTarget?.let(::connect) }

/** Tên hiển thị của host: NSD, rồi host đã ghép, rồi địa chỉ. */
internal fun ViewerController.nameOf(target: ViewerTarget?): String {
    target ?: return ""
    return target.name ?: hosts.firstOrNull { it.host == target.host && it.port == target.port }?.name
        ?: knownHosts.firstOrNull { it.lastAddress == target.address }?.name ?: target.address
}

fun ViewerController.pairWithQr(text: String) {
    val uri = try { PairingURI.parse(text) } catch (e: CryptoException) {
        failure = ConnectionFailure("Mã QR không phải của Xdesk", false)
        return
    }
    // 127.0.0.1 trong QR là chính Mac (chỉ bản Debug), trên điện thoại sẽ trỏ về máy mình nên bỏ qua.
    val targets = uri.addresses.mapNotNull(ViewerTarget::parse).filterNot { it.host == "127.0.0.1" || it.host == "::1" || it.host == "localhost" }
    start(targets, ViewerAuth.Qr(uri), isPairing = true)
}

/** Mở màn ghép đôi, nhớ `target` (host vừa chọn hoặc nhập tay; null = chỉ quét QR). `startOnSas` mở thẳng tab "So mã 6 số". */
fun ViewerController.openPairing(target: ViewerTarget?, startOnSas: Boolean = false) {
    pairTarget = target
    pairOnSas = startOnSas
    screen = Screen.PAIR
}

/** Lớp phủ "Đang kết nối" hiện từ lúc chạm Mac tới khi có khung hình đầu tiên; màn mã SAS có giao diện riêng. */
val ViewerController.awaitingFrame: Boolean get() = sasCode == null && (connecting || (streaming && !progress.frameShown))
