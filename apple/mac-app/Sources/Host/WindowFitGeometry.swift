import CoreGraphics

/// Hình học thuần của "co giãn cửa sổ cho vừa màn hình" (toạ độ AX: gốc trên-trái, y hướng xuống).
enum WindowFitGeometry {
    /// Khung cửa sổ lấp đầy `target`; cửa sổ không co nổi (kích thước tối thiểu `minSize` lớn hơn `target` theo trục nào)
    /// thì giữ kích thước tối thiểu ở trục đó và căn giữa theo trục đó, phần thừa tràn đều hai phía.
    static func frame(minSize: CGSize, in target: CGRect) -> CGRect {
        let width = max(target.width, minSize.width), height = max(target.height, minSize.height)
        let x = width > target.width ? target.midX - width / 2 : target.minX
        let y = height > target.height ? target.midY - height / 2 : target.minY
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// `visibleFrame` của NSScreen (gốc dưới-trái) → toạ độ AX; `primaryHeight` là chiều cao `NSScreen.screens[0]`.
    static func axRect(fromVisibleFrame visible: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height)
    }
}

/// Sổ ghi khung gốc của từng cửa sổ: chỉ nhớ lần đầu (co lại nhiều lần vẫn khôi phục về khung người dùng đặt).
struct WindowFrameLedger<Key: Hashable> {
    private var originals: [Key: CGRect] = [:]

    var count: Int { originals.count }

    func contains(_ key: Key) -> Bool { originals[key] != nil }

    mutating func remember(_ key: Key, frame: CGRect) {
        if originals[key] == nil { originals[key] = frame }
    }

    mutating func forget(_ key: Key) { originals[key] = nil }

    /// Lấy toàn bộ khung gốc để khôi phục và xoá sổ.
    mutating func drain() -> [(key: Key, frame: CGRect)] {
        defer { originals.removeAll() }
        return originals.map { (key: $0.key, frame: $0.value) }
    }
}
