import AppKit
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
        let requestedDisplayID: CGDirectDisplayID? = if config.screenMode == .mirror, let explicitId = config.displayId {
            Self.onlinePhysicalDisplayIDs(excluding: await provider.virtualDisplayIDs).contains(CGDirectDisplayID(explicitId))
                ? CGDirectDisplayID(explicitId)
                : nil
        } else {
            nil
        }
        if config.isNativeMirror || requestedDisplayID != nil {
            let acquired = await provider.acquireNative(displayID: requestedDisplayID)
            let size = CGDisplayCopyDisplayMode(acquired.displayID).flatMap {
                NativeCaptureSize.fit(pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight)
            }
            guard let size else { throw TransportError.rejected(reason: "display", detail: "không đọc được độ phân giải màn hình chính") }
            return (acquired, size.width, size.height)
        }
        if config.screenMode == .mirror { await windowFit?.prepare() }
        let width = Int(config.w), height = Int(config.h)
        let extendSide = await extendSideLookup()
        let spec = VirtualDisplaySpec(
            pixelWidth: width, pixelHeight: height, refreshRate: Double(config.fps),
            hiDPI: config.scale >= 2 || (config.screenMode == .mirror && config.fit == .touch),
            mirrorsMac: config.screenMode == .mirror,
            extendSide: extendSide
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

    /// Liệt kê màn hình vật lý đang gắn vào Mac (bỏ màn hình ảo Xdesk), phục vụ chọn màn hình khi có ≥ 2 màn hình.
    func physicalDisplays() async -> [DisplayInfo] {
        let excluded = await provider.virtualDisplayIDs
        let ids = Self.onlinePhysicalDisplayIDs(excluding: excluded)
        let mainId = CGMainDisplayID()
        let screenNames: [CGDirectDisplayID: String] = await MainActor.run {
            var map: [CGDirectDisplayID: String] = [:]
            for screen in NSScreen.screens {
                if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                    map[CGDirectDisplayID(num.uint32Value)] = screen.localizedName
                }
            }
            return map
        }
        var secondaryIndex = 1
        var list: [DisplayInfo] = []
        for id in ids {
            let isMain = (id == mainId)
            let mode = CGDisplayCopyDisplayMode(id)
            let w = UInt32(max(1, mode?.pixelWidth ?? CGDisplayPixelsWide(id)))
            let h = UInt32(max(1, mode?.pixelHeight ?? CGDisplayPixelsHigh(id)))
            let fallbackName = isMain ? "Màn hình chính" : "Màn hình phụ \(secondaryIndex)"
            if !isMain { secondaryIndex += 1 }
            let rawName = screenNames[id]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (rawName?.isEmpty == false ? rawName! : fallbackName)
            list.append(DisplayInfo(id: id, name: name, width: w, height: h, isMain: isMain))
        }
        return list.sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            return lhs.id < rhs.id
        }
    }

    private static func onlinePhysicalDisplayIDs(excluding excluded: Set<CGDirectDisplayID>) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { !excluded.contains($0) }
    }
}
