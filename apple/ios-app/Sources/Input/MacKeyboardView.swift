import SwiftUI
import XdeskInput

/// Bàn phím Mac ANSI vẽ bằng SwiftUI (chỉ hiển thị) + lớp chạm UIKit đa điểm phía trên.
/// Khung phím tính từ kích thước thật (`MacKeyboardGeometry`): đủ cao thì có hàng F, thiếu thì dùng phím `fn`.
struct MacKeyboardView: View {
    let keyboard: MacKeyboardModel
    let minKeyHeight: CGFloat
    /// Bong bóng phóng chữ phía trên phím đang nhấn (chỉ khi màn dọc, ngón che mất nhãn).
    let showsBubble: Bool

    var body: some View {
        GeometryReader { proxy in
            let geometry = MacKeyboardGeometry(available: proxy.size, minKeyHeight: minKeyHeight, fnLayerOn: keyboard.fnLayerOn)
            let controller = keyboard.controller
            let pressed = controller.pressedUsages
            let shift = controller.activeMods.contains(.shift)
            ZStack(alignment: .topLeading) {
                ForEach(visibleKeys(geometry)) { key in
                    if let frame = geometry.frames[key.usage] {
                        keyCap(key, controller: controller, isPressed: pressed.contains(key.usage), shift: shift)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
                if showsBubble {
                    bubbles(geometry, pressed: pressed, shift: shift, capsLock: controller.capsLockOn)
                }
                MacKeyboardTouchSurface(
                    geometry: geometry,
                    onDown: { keyboard.touchDown(touchId: $0, usage: $1) },
                    onUp: { keyboard.touchUp(touchId: $0) }
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func visibleKeys(_ geometry: MacKeyboardGeometry) -> [MacKey] {
        let rows = geometry.isCompact ? MacKeyboardLayout.compactRows(fnLayer: keyboard.fnLayerOn) : MacKeyboardLayout.rows
        return rows.flatMap { $0 }
    }

    private func bubbles(_ geometry: MacKeyboardGeometry, pressed: Set<UInt16>, shift: Bool, capsLock: Bool) -> some View {
        ForEach(MacKeyboardLayout.allKeys.filter { pressed.contains($0.usage) && ($0.kind == .letter || $0.kind == .symbol) }) { key in
            if let frame = geometry.frames[key.usage] {
                Text(key.displayLabel(shift: shift, capsLock: capsLock))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: max(frame.width + 12, 44), height: 52)
                    .background(BrandPalette.primaryFill, in: RoundedRectangle(cornerRadius: 10))
                    .position(x: min(max(frame.midX, 24), geometry.size.width - 24), y: max(frame.minY - 34, 26))
                    .allowsHitTesting(false)
            }
        }
    }

    private func keyCap(_ key: MacKey, controller: MacKeyboardController, isPressed: Bool, shift: Bool) -> some View {
        let state = controller.state(ofModifierUsage: key.usage)
        let isCapsOn = key.kind == .capsLock && controller.capsLockOn
        let isFnOn = key.kind == .fnLayer && keyboard.fnLayerOn
        let highlighted = isPressed || state != .off || isFnOn
        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 6)
                .fill(highlighted ? BrandPalette.primaryFill : BrandPalette.overlayKey)
            Text(key.displayLabel(shift: shift, capsLock: controller.capsLockOn))
                .font(.system(size: fontSize(key), weight: .medium))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .foregroundStyle(.white)
                .padding(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if isCapsOn || state == .locked {
                Circle()
                    .fill(isCapsOn ? Color.green : Color.white)
                    .frame(width: 5, height: 5)
                    .padding(4)
            }
        }
        .accessibilityHidden(true)
    }

    /// Chữ trên phím ≥ 13 pt; hàng F ≥ 11 pt (hàng thấp hơn).
    private func fontSize(_ key: MacKey) -> CGFloat {
        switch key.kind {
        case .function: 11
        case .modifier, .capsLock, .fnLayer: 13
        case .action where key.label.count > 1: 13
        default: 16
        }
    }
}
