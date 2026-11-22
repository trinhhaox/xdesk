import SwiftUI
import XdeskWire

/// Gợi ý trên cùng + thanh xếp nhanh dưới cùng của chế độ "Chỉnh cửa sổ". Khung viền và cử chỉ nằm ở `WindowAdjustOverlayView`.
struct WindowAdjustChrome: View {
    let controller: WindowAdjustController

    var body: some View {
        VStack(spacing: 0) {
            Text(controller.hasSelection ? "Kéo để dời · chụm hai ngón hoặc kéo góc để đổi cỡ" : "Chạm vào cửa sổ muốn chỉnh")
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(BrandPalette.overlaySurface.opacity(0.85), in: Capsule())
                .padding(.top, 8)
                .allowsHitTesting(false)
            Spacer()
            bar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bar: some View {
        let enabled = controller.hasSelection
        return HStack(spacing: 2) {
            tile("Vừa màn hình", "arrow.up.left.and.arrow.down.right", enabled) { controller.preset(.fill) }
            tile("Trái", "rectangle.lefthalf.inset.filled", enabled) { controller.preset(.left) }
            tile("Phải", "rectangle.righthalf.inset.filled", enabled) { controller.preset(.right) }
            tile("Giữa", "rectangle.center.inset.filled", enabled) { controller.preset(.center) }
            tile("Khôi phục", "arrow.counterclockwise", enabled) { controller.preset(.restore) }
            tile("Xong", "checkmark", true, prominent: true) { controller.exit() }
        }
        .padding(6)
        .background(BrandPalette.overlaySurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func tile(_ title: String, _ symbol: String, _ enabled: Bool, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(prominent ? BrandPalette.primaryFill : Color.white.opacity(enabled ? 0.12 : 0.05)))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.4))
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}
