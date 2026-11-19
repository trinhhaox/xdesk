import UIKit

/// Phản hồi xúc giác nhỏ cho thao tác chạm và kết quả ghép đôi.
@MainActor
enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }

    static func result(success: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
    }
}
