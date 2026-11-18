import Foundation
import XdeskWire

/// Tính `display.config` từ kích thước màn hình viewer (điểm × scale = điểm ảnh gốc).
/// Xoay màn hình chỉ là gọi lại với kích thước đã hoán đổi.
public enum DisplayConfigPlanner {
    public static let maxPixels = 16384.0
    public static let maxScale = 8.0

    /// `nil` nếu đầu vào không hợp lệ (không hữu hạn hoặc ≤ 0). Cạnh làm tròn lên số chẵn (bộ mã hoá 4:2:0) và chặn ở giới hạn wire.
    public static func config(
        pointsWidth: Double, pointsHeight: Double, scale: Double, fps: UInt32 = 60, codec: VideoCodec = .h264,
        mode: ScreenMode = .extend
    ) -> DisplayConfig? {
        guard [pointsWidth, pointsHeight, scale].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let clampedScale = min(scale, maxScale)
        return DisplayConfig(
            w: evenPixels(pointsWidth * clampedScale), h: evenPixels(pointsHeight * clampedScale),
            scale: clampedScale, fps: fps, codec: codec, mode: mode == .extend ? nil : mode
        )
    }

    private static func evenPixels(_ value: Double) -> UInt32 {
        let even = (value / 2).rounded(.up) * 2
        return UInt32(min(max(even, 2), maxPixels))
    }
}
