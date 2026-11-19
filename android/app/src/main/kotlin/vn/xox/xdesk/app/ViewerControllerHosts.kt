package vn.xox.xdesk.app

import vn.xox.xdesk.app.discovery.HostDirectory
import vn.xox.xdesk.app.discovery.PairedEntry
import vn.xox.xdesk.transport.ViewerAuth

/** Danh sách màn chính: gộp Mac đã ghép (kho tin cậy) với Mac thấy qua NSD theo fingerprint. */
val ViewerController.directory: HostDirectory get() = HostDirectory.merge(knownHosts, hosts)

/** Kết nối Mac đã ghép: thử điểm cuối NSD trước rồi địa chỉ đã lưu; cả hai hỏng thì hiện thẻ lỗi quen thuộc. */
fun ViewerController.connectPaired(entry: PairedEntry) {
    val targets = entry.connectTargets()
    if (targets.isEmpty()) {
        failure = ConnectionFailure("Chưa thấy ${entry.known.name} trên mạng và chưa có địa chỉ đã lưu.", false, hostName = entry.known.name)
        return
    }
    start(targets, ViewerAuth.Automatic)
}

/** Quên một Mac đã ghép; nếu đang nối đúng Mac đó thì ngắt trước. Khoá của các Mac khác giữ nguyên. */
fun ViewerController.forgetHost(id: String) {
    if (session?.connectedHostId == id) disconnect()
    container.knownHosts.remove(id)
    knownHosts = container.knownHosts.all()
}
