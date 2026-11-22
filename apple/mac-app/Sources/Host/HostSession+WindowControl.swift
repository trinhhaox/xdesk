import CoreGraphics
import Foundation
import XdeskWire

extension HostSession {
    private static let noInputMessage = "Thiết bị này chưa được cấp quyền điều khiển Mac"
    private static let noAccessibilityMessage = "Mac chưa cấp quyền Trợ năng cho Xdesk"

    /// Tạo (lần đầu) và cập nhật dịch vụ chỉnh cửa sổ theo màn hình đang chiếu. Toạ độ viewer = kích thước khung video (px) / `scale`.
    func configureWindowControl(displayID: CGDirectDisplayID, config: DisplayConfig, pixelWidth: Int, pixelHeight: Int) async {
        guard negotiatedCaps.contains(.windowControl), config.scale > 0 else { return }
        let size = CGSize(width: Double(pixelWidth) / config.scale, height: Double(pixelHeight) / config.scale)
        let service = await windowControlService()
        await service.configure(displayID: displayID, viewerSize: size)
    }

    func shutdownWindowControl() async {
        await windowControl?.shutdown()
        windowControl = nil
    }

    func handleWindowPick(_ pick: WindowPick) async {
        guard negotiatedCaps.contains(.windowControl) else { return }
        if let denial = await windowControlDenial() { return await sendWindowSelected(.failure(denial)) }
        await windowControl?.pick(x: pick.x, y: pick.y)
    }

    func handleWindowAdjust(_ adjust: WindowAdjust) async {
        guard negotiatedCaps.contains(.windowControl) else { return }
        if let denial = await windowControlDenial() { return await sendWindowSelected(.failure(denial)) }
        let nowMs = HostInputService.uptimeMs
        await windowControl?.enqueue(adjust, nowMs: nowMs)
    }

    /// Quyền được kiểm lại mỗi lần: tắt `input` hoặc thu hồi Trợ năng giữa phiên là dừng ngay.
    private func windowControlDenial() async -> String? {
        guard await livePermissions().input else { return Self.noInputMessage }
        guard AccessibilityPermission.isGranted else { return Self.noAccessibilityMessage }
        return nil
    }

    private func windowControlService() async -> WindowControlService {
        if let windowControl { return windowControl }
        let connection = connection
        let service = await MainActor.run {
            WindowControlService(fitter: windowFit) { selected in
                _ = try? await connection.send(.windowSelected(selected))
            }
        }
        windowControl = service
        return service
    }

    private func sendWindowSelected(_ selected: WindowSelected) async {
        _ = try? await connection.send(.windowSelected(selected))
    }
}
