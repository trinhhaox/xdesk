import SwiftUI

/// Thanh trên gọn một hàng cho 3 chế độ điều khiển: tên Mac | menu chọn chế độ (+ nút gạt kiểu bàn phím) | Khóa, Ngắt.
/// Cao 48 (dọc) / 36 (ngang); phần chạm của nút vẫn ≥ 36.
struct ControlTopBar: View {
    let model: StreamViewModel
    let isLandscape: Bool

    @AppStorage(KeyboardPanelMode.storageKey) private var keyboardModeRaw = KeyboardPanelMode.macKeyboard.rawValue

    static func height(isLandscape: Bool) -> CGFloat { isLandscape ? 36 : 48 }

    private var keyboardMode: KeyboardPanelMode { KeyboardPanelMode(rawValue: keyboardModeRaw) ?? .macKeyboard }

    var body: some View {
        HStack(spacing: 8) {
            Text(model.connectingName ?? "Điều khiển Mac")
                .font(.system(size: isLandscape ? 14 : 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            WorkModeMenu(activeMode: model.activeWorkMode, height: Self.height(isLandscape: isLandscape) - 8) { mode in
                model.switchWorkMode(to: mode)
            }

            if model.activeWorkMode == .keyboard {
                iconButton(keyboardMode.toggled.symbol, label: "Chuyển sang \(keyboardMode.toggled.title)", tint: .white.opacity(0.9)) {
                    keyboardModeRaw = keyboardMode.toggled.rawValue
                }
            }

            iconButton("lock.fill", label: "Khóa Mac", tint: .white.opacity(0.9)) {
                Task { await model.session.sendSystemLock() }
            }
            iconButton("xmark.circle.fill", label: "Ngắt kết nối", tint: BrandPalette.danger) {
                Task { await model.disconnect() }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height(isLandscape: isLandscape))
        .background(BrandPalette.overlayCard.opacity(0.6))
    }

    private func iconButton(_ symbol: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(tint)
                .frame(width: 40, height: Self.height(isLandscape: isLandscape))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
