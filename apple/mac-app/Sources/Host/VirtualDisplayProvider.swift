import CoreGraphics
import Foundation

/// Màn hình mà host sẽ capture: mở rộng (màn hình ảo mới) hoặc phản chiếu màn hình chính khi API riêng không dùng được.
enum DisplayMode: Sendable, Equatable {
    case extend
    case mirror
    /// Bản sao "Giống màn hình Mac": capture màn hình chính thật, không tạo/đổi/phản chiếu màn hình nào.
    case native
}

struct VirtualDisplaySpec: Sendable, Equatable {
    var name = "Xdesk"
    var pixelWidth: Int
    var pixelHeight: Int
    var refreshRate: Double
    var hiDPI: Bool
    /// Bản sao: màn hình Mac phản chiếu màn hình ảo (desktop đổi theo kích thước viewer) thay vì mở rộng.
    var mirrorsMac = false
    /// Hướng đặt màn hình ảo khi mở rộng.
    var extendSide: ExtendSide = .right
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
    private var handles: [String: any VirtualDisplayHandle] = [:]
    private(set) var activeDisplays: [String: AcquiredDisplay] = [:]

    var activeDisplay: AcquiredDisplay? { activeDisplays["default"] }
    /// ID các màn hình ảo Xdesk đang tạo (loại khỏi danh sách màn hình vật lý cho viewer chọn).
    var virtualDisplayIDs: Set<CGDirectDisplayID> {
        Set(activeDisplays.values.filter { $0.mode == .extend }.map(\.displayID))
    }

    init(backend: any VirtualDisplayBackend = CGVirtualDisplayBackend(), mainDisplayID: @escaping () -> CGDirectDisplayID = { CGMainDisplayID() }) {
        self.backend = backend
        self.mainDisplayID = mainDisplayID
    }

    func acquire(_ spec: VirtualDisplaySpec) -> AcquiredDisplay {
        acquire(named: "default", spec: spec)
    }

    func acquire(named name: String, spec: VirtualDisplaySpec) -> AcquiredDisplay {
        release(named: name)
        let acquired: AcquiredDisplay
        if backend.isAvailable {
            do {
                var modifiedSpec = spec
                if name != "default" && spec.name == "Xdesk" {
                    modifiedSpec.name = "Xdesk \(name)"
                }
                let created = try backend.create(modifiedSpec)
                handles[name] = created
                acquired = AcquiredDisplay(displayID: created.displayID, mode: .extend, fallbackReason: nil)
            } catch {
                acquired = mirror(reason: "tạo màn hình ảo thất bại: \(error.localizedDescription)")
            }
        } else {
            acquired = mirror(reason: "CGVirtualDisplay không khả dụng")
        }
        activeDisplays[name] = acquired
        return acquired
    }

    /// Giống màn hình Mac: dùng thẳng màn hình thật (`displayID` hoặc màn hình chính), không đụng cấu hình màn hình.
    func acquireNative(displayID: CGDirectDisplayID? = nil) -> AcquiredDisplay {
        release(named: "default")
        let targetID = displayID ?? mainDisplayID()
        let acquired = AcquiredDisplay(displayID: targetID, mode: .native, fallbackReason: nil)
        activeDisplays["default"] = acquired
        return acquired
    }

    /// Huỷ màn hình ảo (nếu có).
    func release() {
        release(named: "default")
    }

    func release(named name: String) {
        handles.removeValue(forKey: name)
        activeDisplays.removeValue(forKey: name)
    }

    func releaseAll() {
        handles.removeAll()
        activeDisplays.removeAll()
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
        if spec.mirrorsMac {
            try DisplayArrangement.mirrorMac(onto: display.displayID)
        } else {
            let logicalW = Int32(spec.hiDPI ? spec.pixelWidth / 2 : spec.pixelWidth)
            let logicalH = Int32(spec.hiDPI ? spec.pixelHeight / 2 : spec.pixelHeight)
            try DisplayArrangement.extend(newDisplay: display.displayID, side: spec.extendSide, logicalSize: (logicalW, logicalH))
        }
        // Sau khi sắp xếp: cấu hình mirror/extend đặt lại mode về 1× nên chọn Retina trước đó bị mất (desktop Mac hiện đủ pixel
        // thay vì điểm = pixel / 2, chữ rất nhỏ trên viewer).
        if spec.hiDPI { DisplayArrangement.applyRetinaMode(display.displayID, pixels: (spec.pixelWidth, spec.pixelHeight)) }
        return RealVirtualDisplay(display: display)
    }
}

private final class RealVirtualDisplay: VirtualDisplayHandle {
    private let display: XDVirtualDisplay
    var displayID: CGDirectDisplayID { display.displayID }
    init(display: XDVirtualDisplay) { self.display = display }
}
