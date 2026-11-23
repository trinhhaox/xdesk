import CoreGraphics

/// Hình học thuần của "co giãn cửa sổ cho vừa màn hình" (toạ độ AX: gốc trên-trái, y hướng xuống).
enum WindowFitGeometry {
    /// Khung cửa sổ lấp đầy `target`; cửa sổ không co nổi (kích thước tối thiểu `minSize` lớn hơn `target` theo trục nào)
    /// thì giữ kích thước tối thiểu và **neo trên-trái**: thanh tiêu đề, nút đóng và phần đầu nội dung luôn nằm trong màn hình
    /// (căn giữa làm mất cả hai mép trên màn hình điện thoại hẹp); phần thừa xem bằng "Chỉnh cửa sổ" hoặc kéo khung hình.
    static func frame(minSize: CGSize, in target: CGRect) -> CGRect {
        CGRect(x: target.minX, y: target.minY, width: max(target.width, minSize.width), height: max(target.height, minSize.height))
    }

    /// Cửa sổ đã co trước đó nhưng giờ lệch ra ngoài màn hình (app tự đổi khung, mở lại, kéo lệch): cần co lại.
    /// Cửa sổ quá khổ đã neo trên-trái thì không tính là lệch, tránh co đi co lại mãi.
    static func needsRefit(_ frame: CGRect, in target: CGRect, tolerance: CGFloat = 1) -> Bool {
        if frame.minX < target.minX - tolerance || frame.minY < target.minY - tolerance { return true }
        let fitsWidth = frame.width <= target.width + tolerance, fitsHeight = frame.height <= target.height + tolerance
        return (fitsWidth && frame.maxX > target.maxX + tolerance) || (fitsHeight && frame.maxY > target.maxY + tolerance)
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
