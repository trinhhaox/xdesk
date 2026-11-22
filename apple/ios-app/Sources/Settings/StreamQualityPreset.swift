import Foundation

/// Tốc độ khung hình mục tiêu khi phát hình; luôn giới hạn theo tần số quét tối đa của màn hình thiết bị.
enum StreamQualityPreset: String, CaseIterable, Identifiable {
    case saver30
    case standard60
    case high120

    var id: String { rawValue }

    var targetFps: Int {
        switch self {
        case .saver30: 30
        case .standard60: 60
        case .high120: 120
        }
    }

    var shortLabel: String { "\(targetFps) fps" }

    func effectiveFps(maxDeviceFps: Int) -> Int {
        min(targetFps, max(30, maxDeviceFps))
    }

    func footer(maxDeviceFps: Int) -> String {
        let capped = effectiveFps(maxDeviceFps: maxDeviceFps)
        switch self {
        case .saver30:
            return "Tiết kiệm pin và băng thông, phù hợp văn bản và công việc văn phòng."
        case .standard60:
            return "Cân bằng độ mượt và thời lượng pin (mặc định)."
        case .high120:
            return capped < 120
                ? "Ưu tiên mượt tối đa (tự giới hạn ở \(capped) fps theo màn hình thiết bị này)."
                : "Mượt tối đa 120 fps, tốn pin và băng thông hơn."
        }
    }
}
