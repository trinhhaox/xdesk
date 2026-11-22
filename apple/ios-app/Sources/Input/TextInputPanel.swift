import SwiftUI
import XdeskInput

/// Kiểu "Gõ văn bản": ô nhập (tiếng Việt) + Gửi, phím bổ trợ và phím tắt. Ngang: toàn bộ vừa khít không cuộn
/// (ô nhập một hàng, phím đặc biệt 2 hàng tràn rộng); dọc: cuộn được như cũ.
struct TextInputPanel: View {
    let model: StreamViewModel
    let isLandscape: Bool

    @State private var inputText = ""
    @State private var activeMods: InputModifiers = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        if isLandscape {
            VStack(spacing: 6) {
                inputRow
                keyRow([.mod("⌘", .command), .mod("⌥", .option), .mod("⌃", .control), .mod("⇧", .shift),
                        .key("esc", 0x29), .key("tab", 0x2B), .key("space", 0x2C), .key("⌫", 0x2A), .key("↩", 0x28)])
                keyRow([.key("⌘C", 0x06, .command), .key("⌘V", 0x19, .command), .key("⌘A", 0x04, .command),
                        .key("←", 0x50), .key("↑", 0x52), .key("↓", 0x51), .key("→", 0x4F)])
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    inputRow
                    keyRow([.mod("⌘ Cmd", .command), .mod("⌥ Opt", .option), .mod("⌃ Ctrl", .control), .mod("⇧ Shift", .shift)])
                        .frame(height: 44)
                    keyRow([.key("Esc", 0x29), .key("Tab", 0x2B), .key("Space", 0x2C), .key("⌫ Del", 0x2A), .key("↩ Enter", 0x28)])
                        .frame(height: 46)
                    keyRow([.key("⌘ C", 0x06, .command), .key("⌘ V", 0x19, .command), .key("⌘ A", 0x04, .command)])
                        .frame(height: 46)
                    keyRow([.key("←", 0x50), .key("↑", 0x52), .key("↓", 0x51), .key("→", 0x4F)])
                        .frame(height: 46)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField(
                "Nhập tiếng Việt / văn bản sang Mac…",
                text: $inputText,
                prompt: Text("Nhập tiếng Việt / văn bản sang Mac…").foregroundStyle(.white.opacity(0.45))
            )
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(BrandPalette.overlayCard, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), lineWidth: 1))
            .foregroundStyle(.white)
            .focused($isInputFocused)
            .submitLabel(.send)
            .onSubmit { sendTypedText() }

            Button("Gửi") { sendTypedText() }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(inputText.isEmpty ? BrandPalette.overlayKey : BrandPalette.primaryFill, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(inputText.isEmpty ? .white.opacity(0.45) : .white)
                .disabled(inputText.isEmpty)
        }
    }

    private func sendTypedText() {
        guard !inputText.isEmpty else { return }
        let text = inputText
        inputText = ""
        Task { _ = await model.session.sendText(text) }
    }

    // MARK: Phím

    private enum Cell {
        case key(String, UInt16, InputModifiers)
        case mod(String, InputModifiers)

        static func key(_ label: String, _ usage: UInt16) -> Cell { .key(label, usage, []) }
    }

    private func keyRow(_ cells: [Cell]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                switch cell {
                case let .key(label, usage, extra): keyButton(label, usage: usage, extra: extra)
                case let .mod(label, mod): modButton(label, mod)
                }
            }
        }
    }

    private func keyButton(_ label: String, usage: UInt16, extra: InputModifiers) -> some View {
        let mods = activeMods.union(extra)
        return Button {
            Haptics.light()
            model.session.sendInput([.key(usage: usage, down: true, mods: mods), .key(usage: usage, down: false, mods: mods)])
        } label: {
            keyLabel(label, highlighted: false)
        }
        .buttonStyle(.plain)
    }

    private func modButton(_ label: String, _ mod: InputModifiers) -> some View {
        let active = activeMods.contains(mod)
        return Button {
            Haptics.light()
            if active { activeMods.remove(mod) } else { activeMods.insert(mod) }
        } label: {
            keyLabel(label, highlighted: active)
        }
        .buttonStyle(.plain)
    }

    private func keyLabel(_ label: String, highlighted: Bool) -> some View {
        Text(label)
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 34)
            .background(highlighted ? BrandPalette.primaryFill : BrandPalette.overlayKey, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
    }
}
