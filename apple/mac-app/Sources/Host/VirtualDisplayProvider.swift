import CoreGraphics
import Foundation

/// Màn hình mà host sẽ capture: mở rộng (màn hình ảo mới) hoặc phản chiếu màn hình chính khi API riêng không dùng được.
enum DisplayMode: Sendable, Equatable {
    case extend
    case mirror
}

struct VirtualDisplaySpec: Sendable, Equatable {
    var name = "Xdesk"
    var pixelWidth: Int
    var pixelHeight: Int
    var refreshRate: Double
    var hiDPI: Bool
}

/// Màn hình ảo đang sống; huỷ (deinit) = màn hình biến mất.
protocol VirtualDisplayHandle: AnyObject {
    var displayID: CGDirectDisplayID { get }
}

/// Cách tạo màn hình ảo, tách khỏi CGVirtualDisplay để test fallback bằng đối tượng giả.
protocol VirtualDisplayBackend {
    var isAvailable: Bool { get }
    func create(_ spec: VirtualDisplaySpec) throws -> any VirtualDisplayHandle
}

/// Kết quả cấp màn hình (chỉ dữ liệu; màn hình ảo thật do provider giữ).
struct AcquiredDisplay: Sendable, Equatable {
    let displayID: CGDirectDisplayID
    let mode: DisplayMode
    /// Lý do không dùng được màn hình ảo (nil nếu đã tạo thành công).
    let fallbackReason: String?
}

/// Sở hữu vòng đời màn hình ảo của một phiên. Không bao giờ crash: lỗi → mirror màn hình chính.
@MainActor
final class VirtualDisplayProvider {
    private let backend: any VirtualDisplayBackend
    private let mainDisplayID: () -> CGDirectDisplayID
    private var handle: (any VirtualDisplayHandle)?
    private(set) var activeDisplay: AcquiredDisplay?

    init(backend: any VirtualDisplayBackend = CGVirtualDisplayBackend(), mainDisplayID: @escaping () -> CGDirectDisplayID = { CGMainDisplayID() }) {
        self.backend = backend
        self.mainDisplayID = mainDisplayID
    }

    func acquire(_ spec: VirtualDisplaySpec) -> AcquiredDisplay {
        release()
        let acquired: AcquiredDisplay
        if backend.isAvailable {
            do {
                let created = try backend.create(spec)
                handle = created
                acquired = AcquiredDisplay(displayID: created.displayID, mode: .extend, fallbackReason: nil)
            } catch {
                acquired = mirror(reason: "tạo màn hình ảo thất bại: \(error.localizedDescription)")
            }
        } else {
            acquired = mirror(reason: "CGVirtualDisplay không khả dụng")
        }
        activeDisplay = acquired
        return acquired
    }

    /// Huỷ màn hình ảo (nếu có).
    func release() {
        handle = nil
        activeDisplay = nil
    }

    private func mirror(reason: String) -> AcquiredDisplay {
        AcquiredDisplay(displayID: mainDisplayID(), mode: .mirror, fallbackReason: reason)
    }
}

/// Backend thật dựa trên `XDVirtualDisplay` (Obj-C, tra cứu API riêng lúc chạy).
struct CGVirtualDisplayBackend: VirtualDisplayBackend {
    var isAvailable: Bool { XDVirtualDisplay.isSupported }

    func create(_ spec: VirtualDisplaySpec) throws -> any VirtualDisplayHandle {
        let display = try XDVirtualDisplay.create(
            withName: spec.name, pixelWidth: UInt(spec.pixelWidth), pixelHeight: UInt(spec.pixelHeight),
            refreshRate: spec.refreshRate, hiDPI: spec.hiDPI
        )
        try DisplayArrangement.extendRight(newDisplay: display.displayID)
        return RealVirtualDisplay(display: display)
    }
}

private final class RealVirtualDisplay: VirtualDisplayHandle {
    private let display: XDVirtualDisplay
    var displayID: CGDirectDisplayID { display.displayID }
    init(display: XDVirtualDisplay) { self.display = display }
}
