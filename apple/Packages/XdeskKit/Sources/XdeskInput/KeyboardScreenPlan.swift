import CoreGraphics

/// Chia vùng nội dung của chế độ Bàn phím (Mac) thành vùng di chuột + vùng bàn phím theo hướng màn hình.
public struct KeyboardScreenPlan: Sendable, Equatable {
    public static let minKeyHeightPortrait: CGFloat = 40
    public static let minKeyHeightLandscape: CGFloat = 34
    public static let minPadHeight: CGFloat = 120
    public static let padFraction: CGFloat = 0.4

    /// Vùng di chuột (nil khi ngang: bàn phím chiếm toàn bộ).
    public let pad: CGRect?
    public let keyboard: CGRect
    public let minKeyHeight: CGFloat

    public init(size: CGSize) {
        let landscape = size.width > size.height
        minKeyHeight = landscape ? Self.minKeyHeightLandscape : Self.minKeyHeightPortrait
        guard !landscape else {
            pad = nil
            keyboard = CGRect(origin: .zero, size: size)
            return
        }
        // Vùng chuột ~40% nhưng co lại trước (tối thiểu 120) để bàn phím giữ được hàng F; bàn phím không cao quá mức cần.
        let full = MacKeyboardGeometry.fullHeightNeeded(minKeyHeight: minKeyHeight)
        let pitch = size.width / MacKeyboardLayout.rowUnits
        let rowCap = max(pitch * MacKeyboardGeometry.maxRowToPitchRatio, minKeyHeight + MacKeyboardGeometry.gap)
        let natural = rowCap * CGFloat(MacKeyboardLayout.rowHeightScales.reduce(0, +))
        let padWanted = max(Self.minPadHeight, size.height * Self.padFraction)
        let padHeight = max(Self.minPadHeight, min(padWanted, size.height - full))
        let keyboardHeight = min(size.height - padHeight, max(natural, full))
        let padFinal = size.height - keyboardHeight
        pad = CGRect(x: 0, y: 0, width: size.width, height: padFinal)
        keyboard = CGRect(x: 0, y: padFinal, width: size.width, height: keyboardHeight)
    }
}
