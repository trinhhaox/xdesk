import CoreGraphics

/// Tính khung từng phím từ bảng `MacKeyboardLayout` và kích thước vùng thật; dùng chung cho vẽ và nhận chạm.
/// Quy tắc: phím không thấp hơn `minKeyHeight`; thiếu chỗ thì ẩn hàng F (bố cục gọn, phím `fn`) chứ không ép nhỏ.
public struct MacKeyboardGeometry: Sendable {
    public static let gap: CGFloat = 4
    /// Hàng phím cao tối đa bằng ngần này lần bề rộng một đơn vị phím (tránh phím quá cao trên màn dọc).
    public static let maxRowToPitchRatio: CGFloat = 2

    public let frames: [UInt16: CGRect]
    public let size: CGSize
    /// Bố cục gọn (không hàng F, có phím `fn`) do thiếu chiều cao.
    public let isCompact: Bool

    /// Chiều cao tối thiểu cần cho bố cục đầy đủ (hàng F 70%) với phím cao `minKeyHeight`.
    public static func fullHeightNeeded(minKeyHeight: CGFloat) -> CGFloat {
        (minKeyHeight + gap) * MacKeyboardLayout.rowHeightScales.reduce(0, +)
    }

    public static func compactHeightNeeded(minKeyHeight: CGFloat) -> CGFloat {
        (minKeyHeight + gap) * CGFloat(MacKeyboardLayout.compactRows(fnLayer: false).count)
    }

    public init(available: CGSize, minKeyHeight: CGFloat, fnLayerOn: Bool = false) {
        let compact = available.height < Self.fullHeightNeeded(minKeyHeight: minKeyHeight)
        let rows = compact ? MacKeyboardLayout.compactRows(fnLayer: fnLayerOn) : MacKeyboardLayout.rows
        let scales = compact ? Array(repeating: 1.0, count: rows.count) : MacKeyboardLayout.rowHeightScales
        let pitch = available.width / MacKeyboardLayout.rowUnits
        let totalScale = CGFloat(scales.reduce(0, +))
        let cap = max(pitch * Self.maxRowToPitchRatio, minKeyHeight + Self.gap)
        let rowHeight = min(cap, available.height / totalScale)

        var map: [UInt16: CGRect] = [:]
        var y: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let height = rowHeight * CGFloat(scales[index])
            var x: CGFloat = 0
            var stackIndex = 0
            for key in row {
                let width = pitch * CGFloat(key.width)
                if key.isHalfHeight {
                    map[key.usage] = Self.frame(x: x, y: y + CGFloat(stackIndex) * height / 2, w: width, h: height / 2)
                    stackIndex += 1
                    if stackIndex == 2 { x += width }
                } else {
                    map[key.usage] = Self.frame(x: x, y: y, w: width, h: height)
                    x += width
                }
            }
            y += height
        }
        frames = map
        size = CGSize(width: available.width, height: y)
        isCompact = compact
    }

    private static func frame(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
        CGRect(x: x + gap / 2, y: y + gap / 2, width: w - gap, height: h - gap)
    }

    public func usage(at point: CGPoint) -> UInt16? {
        // Chạm vào khe giữa các phím vẫn trúng phím gần nhất (nới nửa khe).
        frames.first { $0.value.insetBy(dx: -Self.gap / 2, dy: -Self.gap / 2).contains(point) }?.key
    }
}
