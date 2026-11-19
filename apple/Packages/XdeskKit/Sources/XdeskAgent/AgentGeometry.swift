import Foundation

/// Hệ toạ độ của màn hình agent: gốc trên-trái, đơn vị pixel của màn hình agent (màn hình ảo không HiDPI nên điểm = pixel).
public struct AgentDisplayGeometry: Sendable, Equatable {
    public static let maxScreenshotEdge = 1568
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) { self.width = width; self.height = height }

    public func contains(x: Double, y: Double) -> Bool {
        x.isFinite && y.isFinite && x >= 0 && y >= 0 && x < Double(width) && y < Double(height)
    }

    /// Cạnh dài ≤ 1568 px để tiết kiệm token; không phóng to ảnh nhỏ.
    public var screenshotSize: (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > Self.maxScreenshotEdge else { return (width, height) }
        let scale = Double(Self.maxScreenshotEdge) / Double(longest)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    public var coordinateNote: String {
        let image = screenshotSize
        let scale = Double(image.width) / Double(width)
        return "Ảnh \(image.width)x\(image.height) px của màn hình agent \(width)x\(height). Mọi toạ độ x,y của tool tính theo pixel màn hình agent "
            + "(gốc trên-trái, x 0..\(width - 1), y 0..\(height - 1)); toạ độ trên ảnh nhân với \(String(format: "%.4f", 1 / scale)) để ra toạ độ tool."
    }
}

/// Phần tử giao diện (frame theo toạ độ màn hình agent) để agent click theo ref.
public struct UiElement: Sendable, Equatable {
    public var ref: String
    public var role: String
    public var label: String
    public var x: Double, y: Double, width: Double, height: Double

    public init(ref: String, role: String, label: String, x: Double, y: Double, width: Double, height: Double) {
        self.ref = ref; self.role = role; self.label = label; self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var center: (x: Double, y: Double) { (x + width / 2, y + height / 2) }

    public var line: String {
        let name = label.isEmpty ? "" : " \"\(label.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " "))\""
        return "\(ref) \(role)\(name) [\(Int(x)),\(Int(y)),\(Int(width)),\(Int(height))]"
    }
}

/// Bảng ref của lần `xdesk_ui_tree` gần nhất; lần gọi sau thay thế toàn bộ nên ref cũ hết hiệu lực.
public final class UiRefTable: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [String: UiElement] = [:]

    public init() {}

    public func replace(with new: [UiElement]) { lock.withLock { elements = Dictionary(new.map { ($0.ref, $0) }, uniquingKeysWith: { first, _ in first }) } }
    public func element(_ ref: String) -> UiElement? { lock.withLock { elements[ref] } }
    public var count: Int { lock.withLock { elements.count } }
}
