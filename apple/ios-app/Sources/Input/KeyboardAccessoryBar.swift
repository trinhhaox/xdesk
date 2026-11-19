import SwiftUI
import UIKit
import XdeskInput
import XdeskWire

/// `inputAccessoryView` gắn trên bàn phím hệ thống: bọc `KeyboardAccessoryBar` (SwiftUI) trong `UIInputView`.
@MainActor
final class KeyboardAccessoryView: UIInputView {
    static let barHeight: CGFloat = 48

    init(controller: TextComposerController) {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.barHeight), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        backgroundColor = .secondarySystemBackground
        let content = UIHostingConfiguration { KeyboardAccessoryBar(controller: controller) }.margins(.all, 0).makeContentView()
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: Self.barHeight),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Phím riêng của Mac mà bàn phím iOS không có. ⌃ ⌥ ⌘ ⇧ là phím dính: chạm một lần áp cho phím kế tiếp, chạm hai lần để khoá.
/// Không có ⌫ và ↩ vì bàn phím hệ thống đã có sẵn. Hàng phím cuộn ngang (vừa mọi cỡ màn hình, kể cả xoay ngang), nút ẩn bàn phím ghim bên phải.
struct KeyboardAccessoryBar: View {
    let controller: TextComposerController
    private static let keySize: CGFloat = 44
    private static let barColor = Color(uiColor: .secondarySystemBackground)
    private static let keyColor = Color(uiColor: .tertiarySystemBackground)

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    modifierKey("command", "Command", .command)
                    modifierKey("option", "Option", .option)
                    modifierKey("control", "Control", .control)
                    modifierKey("shift", "Shift", .shift)
                    separator
                    plainKey(.text("Esc"), "Escape", HidUsage.escape)
                    plainKey(.text("Tab"), "Tab", HidUsage.tab)
                    separator
                    plainKey(.symbol("arrow.left"), "Mũi tên trái", HidUsage.left)
                    plainKey(.symbol("arrow.down"), "Mũi tên xuống", HidUsage.down)
                    plainKey(.symbol("arrow.up"), "Mũi tên lên", HidUsage.up)
                    plainKey(.symbol("arrow.right"), "Mũi tên phải", HidUsage.right)
                }
                .padding(.horizontal, 8)
            }
            Rectangle().fill(Color(uiColor: .separator)).frame(width: 1, height: 28)
            Button { controller.isActive = false } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(uiColor: .label))
                    .frame(width: 52, height: KeyboardAccessoryView.barHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ẩn bàn phím")
        }
        .frame(height: KeyboardAccessoryView.barHeight)
        .background(Self.barColor)
    }

    private enum Face { case text(String), symbol(String) }

    private var separator: some View {
        Rectangle().fill(Color(uiColor: .separator)).frame(width: 1, height: 24).padding(.horizontal, 2)
    }

    private func plainKey(_ face: Face, _ name: String, _ usage: UInt16) -> some View {
        Button { controller.tapKey(usage) } label: { keyFace(face, state: .off) }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
    }

    private func modifierKey(_ symbol: String, _ name: String, _ modifier: InputModifiers) -> some View {
        let state = controller.modifiers.state(of: modifier)
        return Button { controller.tapModifier(modifier) } label: { keyFace(.symbol(symbol), state: state) }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityValue(state == .off ? "Tắt" : (state == .armed ? "Áp cho phím kế tiếp" : "Đã khoá"))
            .accessibilityHint("Chạm một lần cho phím kế tiếp, chạm hai lần để khoá")
            .accessibilityAddTraits(state == .off ? [] : .isSelected)
    }

    private func keyFace(_ face: Face, state: StickyModifiers.State) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        return Group {
            switch face {
            case .text(let text): Text(text).font(.system(size: 16, weight: .semibold))
            case .symbol(let name): Image(systemName: name).font(.system(size: 18, weight: .semibold))
            }
        }
        .frame(minWidth: Self.keySize, minHeight: Self.keySize)
        .foregroundStyle(state == .locked ? Color.white : Color(uiColor: .label))
        .background(shape.fill(state == .locked ? BrandPalette.primary : (state == .armed ? BrandPalette.primary.opacity(0.22) : Self.keyColor)))
        .overlay(shape.stroke(state == .off ? Color(uiColor: .separator) : BrandPalette.primary, lineWidth: state == .off ? 0.5 : 2))
        .contentShape(shape)
    }
}
