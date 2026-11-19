import CoreGraphics
import XdeskTransport
import XdeskWire

/// Kích thước encode khi stream màn hình chính thật (Bản sao "Giống màn hình Mac"): giữ tỉ lệ thật, cạnh dài tối đa
/// `maxLongEdge` px (giới hạn bitrate/bộ mã hoá), mỗi cạnh làm tròn xuống số chẵn (4:2:0).
enum NativeCaptureSize {
    static let maxLongEdge = 2560

    static func fit(pixelWidth: Int, pixelHeight: Int, maxLongEdge: Int = NativeCaptureSize.maxLongEdge) -> (width: Int, height: Int)? {
        guard pixelWidth > 0, pixelHeight > 0, maxLongEdge >= 2 else { return nil }
        let long = max(pixelWidth, pixelHeight)
        guard long > maxLongEdge else { return (evenDown(pixelWidth), evenDown(pixelHeight)) }
        return (evenDown(pixelWidth * maxLongEdge / long), evenDown(pixelHeight * maxLongEdge / long))
    }

    private static func evenDown(_ value: Int) -> Int { max(2, value & ~1) }
}

extension HostSession {
    /// Chọn màn hình để capture theo `display.config`: `native` = màn hình chính thật (không đụng cấu hình Mac);
    /// ngược lại = màn hình ảo đúng `w`×`h` (`touch` luôn HiDPI để macOS thấy kích thước logic w/2 × h/2).
    func acquireDisplay(for config: DisplayConfig) async throws -> (display: AcquiredDisplay, width: Int, height: Int) {
        if config.isNativeMirror {
            let acquired = await provider.acquireNative()
            let size = CGDisplayCopyDisplayMode(acquired.displayID).flatMap {
                NativeCaptureSize.fit(pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight)
            }
            guard let size else { throw TransportError.rejected(reason: "display", detail: "không đọc được độ phân giải màn hình chính") }
            return (acquired, size.width, size.height)
        }
        if config.screenMode == .mirror { await windowFit?.prepare() }
        let width = Int(config.w), height = Int(config.h)
        let spec = VirtualDisplaySpec(
            pixelWidth: width, pixelHeight: height, refreshRate: Double(config.fps),
            hiDPI: config.scale >= 2 || (config.screenMode == .mirror && config.fit == .touch),
            mirrorsMac: config.screenMode == .mirror
        )
        return (await provider.acquire(spec), width, height)
    }

    /// Bản sao fitDevice/touch: co cửa sổ app cho vừa màn hình ảo (native/extend không đụng cửa sổ).
    func beginWindowFit(_ config: DisplayConfig, displayID: CGDirectDisplayID) async {
        guard let windowFit, config.screenMode == .mirror, config.fit != .native else { return }
        windowFitActive = true
        await windowFit.begin(displayID: displayID)
    }

    func endWindowFit() async {
        guard windowFitActive else { return }
        windowFitActive = false
        await windowFit?.end()
    }
}
