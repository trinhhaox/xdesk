import CoreGraphics
import Foundation
import XdeskAgent

enum AgentDisplayError: LocalizedError {
    case sizeOutOfRange
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .sizeOutOfRange: "Kích thước màn hình agent phải trong khoảng \(AgentDisplayManager.widthRange.lowerBound)x\(AgentDisplayManager.heightRange.lowerBound) đến \(AgentDisplayManager.widthRange.upperBound)x\(AgentDisplayManager.heightRange.upperBound)"
        case .unavailable(let reason): "Không tạo được màn hình agent: \(reason)"
        }
    }
}

/// Màn hình ảo riêng "Xdesk Agent" (CGVirtualDisplay, không HiDPI nên điểm = pixel). Chỉ chạy khi có màn hình ảo thật:
/// nếu hệ thống chỉ cho phản chiếu màn hình chính thì từ chối, vì agent không bao giờ được điều khiển màn hình của người dùng.
@MainActor
final class AgentDisplayManager {
    static let displayName = "Xdesk Agent"
    static let defaultSize = (width: 1280, height: 800)
    nonisolated static let widthRange = 640...3840
    nonisolated static let heightRange = 480...2160

    private let provider = VirtualDisplayProvider()
    private(set) var displayID: CGDirectDisplayID?

    var bounds: CGRect? { displayID.map { CGDisplayBounds($0) } }

    var geometry: AgentDisplayGeometry? {
        bounds.map { AgentDisplayGeometry(width: Int($0.width), height: Int($0.height)) }
    }

    /// Tạo (hoặc tạo lại khi đổi kích thước). Trả về id màn hình.
    @discardableResult
    func ensure(width: Int = defaultSize.width, height: Int = defaultSize.height, recreate: Bool = false) throws -> CGDirectDisplayID {
        guard Self.widthRange.contains(width), Self.heightRange.contains(height) else { throw AgentDisplayError.sizeOutOfRange }
        if let displayID, !recreate { return displayID }
        let spec = VirtualDisplaySpec(name: Self.displayName, pixelWidth: width, pixelHeight: height, refreshRate: 60, hiDPI: false)
        let acquired = provider.acquire(spec)
        guard acquired.mode == .extend else {
            provider.release()
            displayID = nil
            throw AgentDisplayError.unavailable(acquired.fallbackReason ?? "hệ thống không cho tạo màn hình ảo")
        }
        displayID = acquired.displayID
        return acquired.displayID
    }

    /// Đổi kích thước = huỷ rồi tạo lại. macOS cần một lúc để gỡ màn hình cũ, tạo ngay sẽ lỗi sắp xếp nên thử lại vài lần.
    func recreate(width: Int, height: Int) async throws {
        guard Self.widthRange.contains(width), Self.heightRange.contains(height) else { throw AgentDisplayError.sizeOutOfRange }
        destroy()
        var lastError: Error = AgentDisplayError.unavailable("không rõ lý do")
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(600))
            do { try ensure(width: width, height: height); return } catch { lastError = error }
        }
        throw lastError
    }

    func destroy() {
        provider.release()
        displayID = nil
    }
}
