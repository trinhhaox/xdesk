import XdeskTransport
import XdeskWire

extension ViewerSession {
    /// Chọn cửa sổ trên cùng tại điểm (x, y) của luồng video đang xem. Kết quả về qua `selectedWindow` / `onWindowSelected`.
    public func pickWindow(x: Double, y: Double) async {
        await sendWindowMessage(.windowPick(WindowPick(x: x, y: y)))
    }

    /// Dời / đổi cỡ / xếp cửa sổ đã chọn (xem `WindowAdjust.move/resize/preset`). Host trả `window.selected` với frame mới.
    /// Viewer nên gộp theo khung hình (tối đa 60 lần/giây).
    public func adjustWindow(_ adjust: WindowAdjust) async {
        await sendWindowMessage(.windowAdjust(adjust))
    }

    private func sendWindowMessage(_ message: ControlMessage) async {
        guard state == .streaming, supportsWindowControl, let connection else { return }
        do { _ = try await connection.send(message) }
        catch { log.error("gửi \(message.typeName, privacy: .public) lỗi: \(error.localizedDescription, privacy: .public)") }
    }
}
