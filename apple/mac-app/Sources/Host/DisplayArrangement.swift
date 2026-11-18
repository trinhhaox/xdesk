import CoreGraphics

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

    private static func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
