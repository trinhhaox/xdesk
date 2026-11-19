import Foundation
import XdeskWire

/// Tính `display.config` từ kích thước màn hình viewer (điểm × scale = điểm ảnh gốc).
/// Xoay màn hình chỉ là gọi lại với kích thước đã hoán đổi.
public enum DisplayConfigPlanner {
    public static let maxPixels = 16384.0
    public static let maxScale = 8.0

    /// `nil` nếu đầu vào không hợp lệ (không hữu hạn hoặc ≤ 0). Cạnh làm tròn lên số chẵn (bộ mã hoá 4:2:0) và chặn ở giới hạn wire.
    /// `mirrorFit` chỉ có nghĩa khi `mode == .mirror`: `fitDevice` bị bỏ khỏi wire (mặc định); `touch` gửi kích thước logic × 2 và
    /// scale 2 (xem `TouchScale`); `native` gửi (cạnh dài, cạnh ngắn) để xoay máy không đổi cấu hình (host bỏ qua w/h).
    public static func config(
        pointsWidth: Double, pointsHeight: Double, scale: Double, fps: UInt32 = 60, codec: VideoCodec = .h264,
        mode: ScreenMode = .extend, mirrorFit: MirrorFit = .fitDevice
    ) -> DisplayConfig? {
        guard [pointsWidth, pointsHeight, scale].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let wireMode: ScreenMode? = mode == .extend ? nil : mode
        let fit = mode == .mirror ? mirrorFit : .fitDevice
        var width = pointsWidth, height = pointsHeight, clampedScale = min(scale, maxScale)
        switch fit {
        case .fitDevice: break
        case .touch:
            (width, height) = TouchScale.logicalSize(pointsWidth: pointsWidth, pointsHeight: pointsHeight)
            clampedScale = 2
        case .native: (width, height) = (max(pointsWidth, pointsHeight), min(pointsWidth, pointsHeight))
        }
        let pixelsPerPoint = fit == .touch ? 2 : clampedScale
        return DisplayConfig(
            w: evenPixels(width * pixelsPerPoint), h: evenPixels(height * pixelsPerPoint),
            scale: clampedScale, fps: fps, codec: codec, mode: wireMode, mirrorFit: fit == .fitDevice ? nil : fit
        )
    }

    private static func evenPixels(_ value: Double) -> UInt32 {
        let even = (value / 2).rounded(.up) * 2
        return UInt32(min(max(even, 2), maxPixels))
    }
}
