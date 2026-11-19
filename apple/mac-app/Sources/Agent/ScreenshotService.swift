import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import XdeskAgent

enum ScreenshotError: LocalizedError {
    case noPermission, displayMissing, encodeFailed

    var errorDescription: String? {
        switch self {
        case .noPermission: "Chưa có quyền Ghi màn hình cho Xdesk. \(PermissionsCheck.settingsHint)"
        case .displayMissing: "Không tìm thấy màn hình agent trong danh sách ScreenCaptureKit"
        case .encodeFailed: "Không mã hoá được ảnh PNG"
        }
    }
}

/// Chụp đúng màn hình agent bằng `SCScreenshotManager`, cạnh dài ≤ 1568 px, loại banner và cửa sổ nhạy cảm của Xdesk.
enum ScreenshotService {
    static func capture(displayID: CGDirectDisplayID, geometry: AgentDisplayGeometry) async throws -> Data {
        guard PermissionsCheck.hasScreenRecording else { throw ScreenshotError.noPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw ScreenshotError.displayMissing }
        let secure = SecureWindowRegistry.shared.windowIDs
        let own = ProcessInfo.processInfo.processIdentifier
        let excluded = content.windows.filter { secure.contains($0.windowID) || $0.owningApplication?.processID == own }
        let size = geometry.screenshotSize
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = true
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: excluded), configuration: configuration)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw ScreenshotError.encodeFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScreenshotError.encodeFailed }
        return data as Data
    }
}
