import UIKit

/// Kích thước điểm + scale + tần số quét tối đa của vùng hiển thị; nhân lên ra điểm ảnh gốc khi tạo `display.config`.
struct ScreenMetrics: Equatable {
    let size: CGSize
    let scale: CGFloat
    let maxFps: Int

    init(size: CGSize, scale: CGFloat, maxFps: Int = 60) {
        self.size = size
        self.scale = scale
        self.maxFps = maxFps
    }

    /// Tần số quét tối đa của màn hình thiết bị hiện tại.
    @MainActor
    static func currentMaxFps() -> Int {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return max(30, scene?.screen.maximumFramesPerSecond ?? 60)
    }

    /// Số đo hiện tại của cửa sổ app (lúc chưa có view nào đo được, vd. khởi động / tự kết nối khi debug).
    @MainActor
    static func current() -> ScreenMetrics? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return nil }
        // Vùng an toàn (video không nằm dưới tai thỏ/Dynamic Island): phải khớp kích thước SwiftUI đo ở màn stream.
        let window = scene.windows.first
        let size = window.map { $0.bounds.inset(by: $0.safeAreaInsets).size } ?? scene.screen.bounds.size
        return ScreenMetrics(size: size, scale: scene.screen.scale, maxFps: max(30, scene.screen.maximumFramesPerSecond))
    }
}

/// Gom các thay đổi kích thước (xoay máy, đổi cỡ cửa sổ iPad) thành một lần báo sau khi ổn định,
/// để một lần xoay chỉ gây một lần đổi `display.config`.
@MainActor
final class OrientationObserver {
    private let settleDelay: Duration
    private let onSettled: @MainActor (ScreenMetrics) -> Void
    private var pending: Task<Void, Never>?
    private(set) var latest: ScreenMetrics?

    init(settleDelay: Duration = .milliseconds(350), onSettled: @escaping @MainActor (ScreenMetrics) -> Void) {
        self.settleDelay = settleDelay
        self.onSettled = onSettled
    }

    func update(_ metrics: ScreenMetrics) {
        guard metrics != latest else { return }
        latest = metrics
        pending?.cancel()
        pending = Task { [settleDelay, onSettled] in
            do { try await Task.sleep(for: settleDelay) } catch { return }
            onSettled(metrics)
        }
    }
}
