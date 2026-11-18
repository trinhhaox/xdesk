import CoreGraphics
import Darwin

/// Sắp xếp màn hình ảo vừa tạo: macOS có thể tự đưa nó vào nhóm mirror (màn hình thật bị phản chiếu theo độ phân giải ảo
/// và còn thành "màn hình chính"). Gỡ mirror, trả màn hình thật về gốc (0,0) và đặt màn hình ảo bên phải → màn hình mở rộng.
/// Chỉ áp dụng cho phiên hiện tại (`forSession`): thoát app thì cấu hình tự về như cũ.
enum DisplayArrangement {
    enum ArrangementError: Error, LocalizedError {
        case failed(CGError)
        var errorDescription: String? {
            guard case .failed(let code) = self else { return nil }
            return "Không sắp xếp được màn hình ảo (CGError \(code.rawValue))"
        }
    }

    static func extendRight(newDisplay: CGDirectDisplayID) throws {
        let all = onlineDisplays()
        let others = all.filter { $0 != newDisplay }
        guard let base = others.first(where: { CGDisplayIsBuiltin($0) != 0 }) ?? others.first else { return }
        var config: CGDisplayConfigRef?
        var status = CGBeginDisplayConfiguration(&config)
        guard status == .success, let config else { throw ArrangementError.failed(status) }
        for display in all { CGConfigureDisplayMirrorOfDisplay(config, display, kCGNullDirectDisplay) }
        CGConfigureDisplayOrigin(config, base, 0, 0)
        let baseWidth = CGDisplayCopyDisplayMode(base).map { Int32($0.width) } ?? Int32(CGDisplayBounds(base).width)
        CGConfigureDisplayOrigin(config, newDisplay, baseWidth, 0)
        status = CGCompleteDisplayConfiguration(config, .forSession)
        guard status == .success else { throw ArrangementError.failed(status) }
    }

    /// Bản sao: mọi màn hình thật phản chiếu màn hình ảo → desktop Mac chạy đúng kích thước/tỉ lệ của viewer
    /// (màn hình Mac hiện cùng nội dung, có viền đen nếu tỉ lệ lệch). Màn hình ảo đứng ở (0,0) nên giữ thanh menu.
    /// Màn hình ảo vừa tạo có thể chưa nhận cấu hình mirror ngay → thử lại tối đa ~1 s.
    static func mirrorMac(onto virtualDisplay: CGDirectDisplayID) throws {
        var lastError: Error?
        for _ in 0..<10 {
            do { return try configureMirror(onto: virtualDisplay) } catch { lastError = error }
            usleep(100_000)
        }
        if let lastError { throw lastError }
    }

    private static func configureMirror(onto virtualDisplay: CGDirectDisplayID) throws {
        var config: CGDisplayConfigRef?
        var status = CGBeginDisplayConfiguration(&config)
        guard status == .success, let config else { throw ArrangementError.failed(status) }
        CGConfigureDisplayMirrorOfDisplay(config, virtualDisplay, kCGNullDirectDisplay)
        CGConfigureDisplayOrigin(config, virtualDisplay, 0, 0)
        for display in onlineDisplays() where display != virtualDisplay {
            CGConfigureDisplayMirrorOfDisplay(config, display, virtualDisplay)
        }
        status = CGCompleteDisplayConfiguration(config, .forSession)
        guard status == .success else { throw ArrangementError.failed(status) }
    }

    /// Chọn mode Retina (điểm = điểm ảnh / 2): macOS mặc định chọn mode 1× khiến chữ trên viewer rất nhỏ.
    /// Danh sách mode của màn hình ảo chỉ có sau một lúc, nên thử lại tối đa ~1 s. Trả về false nếu không chọn được.
    @discardableResult
    static func applyRetinaMode(_ display: CGDirectDisplayID, pixels: (width: Int, height: Int)) -> Bool {
        for _ in 0..<20 {
            if let mode = retinaMode(of: display, pixels: pixels), CGDisplaySetDisplayMode(display, mode, nil) == .success { return true }
            usleep(50_000)
        }
        return false
    }

    private static func retinaMode(of display: CGDirectDisplayID, pixels: (width: Int, height: Int)) -> CGDisplayMode? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? []
        return modes.first { $0.pixelWidth == pixels.width && $0.pixelHeight == pixels.height && $0.width * 2 == pixels.width }
    }

    private static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
