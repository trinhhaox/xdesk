package vn.xox.xdesk.app

import vn.xox.xdesk.crypto.CryptoException
import vn.xox.xdesk.crypto.PairingURI
import vn.xox.xdesk.transport.ViewerAuth
import vn.xox.xdesk.transport.ViewerTarget

fun ViewerController.connectManual(text: String) {
    val target = ViewerTarget.parse(text) ?: return run { failure = ConnectionFailure("Địa chỉ phải có dạng host:port", false) }
    start(listOf(target), ViewerAuth.Automatic)
}

fun ViewerController.pairWithQr(text: String) {
    val uri = try { PairingURI.parse(text) } catch (e: CryptoException) {
        failure = ConnectionFailure("Mã QR không phải của Xdesk", false)
        return
    }
    // 127.0.0.1 trong QR là chính Mac (chỉ bản Debug), trên điện thoại sẽ trỏ về máy mình nên bỏ qua.
    val targets = uri.addresses.mapNotNull(ViewerTarget::parse).filterNot { it.host == "127.0.0.1" || it.host == "::1" || it.host == "localhost" }
    start(targets, ViewerAuth.Qr(uri))
}

/** Mở màn ghép đôi, nhớ `target` (host vừa chọn hoặc nhập tay; null = chỉ quét QR). */
fun ViewerController.openPairing(target: ViewerTarget?) {
    pairTarget = target
    screen = Screen.PAIR
}
