import SwiftUI
import UIKit
import XdeskInput
import XdeskViewer
import XdeskWire

/// Màn hình điều khiển: biến iPhone/iPad thành Trackpad cảm ứng lớn và Bàn phím chuyên nghiệp điều khiển Mac từ xa.
struct RemoteTrackpadView: View {
    let model: StreamViewModel
    let onClose: () -> Void

    @State private var selectedTab: RemoteTab = .trackpad
    @State private var cursorX: Float = 0.5
    @State private var cursorY: Float = 0.5
    @State private var activeMods: InputModifiers = []
    @State private var inputText: String = ""
    @State private var isLeftDown = false
    @State private var isRightDown = false
    @FocusState private var isInputFocused: Bool

    enum RemoteTab: String, CaseIterable, Identifiable {
        case trackpad = "Trackpad"
        case keyboard = "Bàn phím"
        case numpadMedia = "Số & Media"
        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .trackpad: return "computermouse.fill"
            case .keyboard: return "keyboard.fill"
            case .numpadMedia: return "play.tv.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(Color.white.opacity(0.15))

            switch selectedTab {
            case .trackpad:
                trackpadArea
            case .keyboard:
                keyboardArea
            case .numpadMedia:
                numpadAndMediaArea
            }
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.12).ignoresSafeArea())
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Button {
                Haptics.light()
                onClose()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "display")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Màn hình")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Picker("", selection: $selectedTab) {
                ForEach(RemoteTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.iconName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            Spacer()

            HStack(spacing: 12) {
                Button {
                    Haptics.light()
                    Task { await model.session.sendSystemLock() }
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.light()
                    Task { await model.disconnect() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 1. Trackpad Area

    private var trackpadArea: some View {
        VStack(spacing: 8) {
            // Vùng cảm ứng Trackpad
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(white: 0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    VStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("Di 1 ngón: Di chuột · 1 chạm: Chuột trái\n2 ngón chạm: Chuột phải · 2 ngón vuốt: Cuộn trang")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            handleTrackpadDrag(translation: value.translation, in: geo.size)
                        }
                        .onEnded { _ in
                            lastDragTranslation = .zero
                        }
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        sendLeftClick()
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Nút chuột vật lý dưới đáy
            HStack(spacing: 12) {
                Button {
                    sendLeftClick()
                } label: {
                    Text("Chuột Trái")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.white.opacity(isLeftDown ? 0.3 : 0.15), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isLeftDown = true }
                        .onEnded { _ in isLeftDown = false }
                )

                Button {
                    sendRightClick()
                } label: {
                    Text("Chuột Phải")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.white.opacity(isRightDown ? 0.3 : 0.15), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isRightDown = true }
                        .onEnded { _ in isRightDown = false }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    @State private var lastDragTranslation: CGSize = .zero

    private func handleTrackpadDrag(translation: CGSize, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let dx = Float((translation.width - lastDragTranslation.width) / size.width) * 1.8
        let dy = Float((translation.height - lastDragTranslation.height) / size.height) * 1.8
        lastDragTranslation = translation

        cursorX = min(1, max(0, cursorX + dx))
        cursorY = min(1, max(0, cursorY + dy))

        model.session.sendInput([.move(x: cursorX, y: cursorY, mods: activeMods)])
    }

    private func sendLeftClick() {
        Haptics.light()
        model.session.sendInput([
            .button(down: true, button: InputButton.left, x: cursorX, y: cursorY, mods: activeMods),
            .button(down: false, button: InputButton.left, x: cursorX, y: cursorY, mods: activeMods)
        ])
    }

    private func sendRightClick() {
        Haptics.light()
        model.session.sendInput([
            .button(down: true, button: InputButton.right, x: cursorX, y: cursorY, mods: activeMods),
            .button(down: false, button: InputButton.right, x: cursorX, y: cursorY, mods: activeMods)
        ])
    }

    // MARK: - 2. Keyboard Area

    private var keyboardArea: some View {
        VStack(spacing: 12) {
            // Khung gõ text tiếng Việt gửi sang Mac
            HStack(spacing: 8) {
                TextField("Nhập văn bản gửi sang Mac…", text: $inputText)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        sendTypedText()
                    }

                if !inputText.isEmpty {
                    Button("Gửi") {
                        sendTypedText()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                    .font(.system(size: 15, weight: .semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Thanh phím bổ trợ Modifier (⌘ ⌥ ⌃ ⇧)
            HStack(spacing: 8) {
                modToggle("⌘ Cmd", .command)
                modToggle("⌥ Option", .option)
                modToggle("⌃ Control", .control)
                modToggle("⇧ Shift", .shift)
            }
            .padding(.horizontal, 16)

            // Hàng phím tiện ích
            HStack(spacing: 8) {
                keyButton("Esc", usage: 0x29)
                keyButton("Tab", usage: 0x2B)
                keyButton("Space", usage: 0x2C)
                keyButton("⌫ Del", usage: 0x2A)
                keyButton("↩ Enter", usage: 0x28)
            }
            .padding(.horizontal, 16)

            // Cụm phím điều hướng mũi tên
            HStack(spacing: 16) {
                Spacer()
                VStack(spacing: 8) {
                    keyButton("↑", usage: 0x52)
                    HStack(spacing: 8) {
                        keyButton("←", usage: 0x50)
                        keyButton("↓", usage: 0x51)
                        keyButton("→", usage: 0x4F)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)

            Spacer()
        }
    }

    private func sendTypedText() {
        guard !inputText.isEmpty else { return }
        let textToSend = inputText
        inputText = ""
        Task {
            _ = await model.session.sendText(textToSend)
        }
    }

    private func modToggle(_ label: String, _ mod: InputModifiers) -> some View {
        let active = activeMods.contains(mod)
        return Button {
            Haptics.light()
            if active {
                activeMods.remove(mod)
            } else {
                activeMods.insert(mod)
            }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(active ? Color.blue : Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func keyButton(_ label: String, usage: UInt16) -> some View {
        Button {
            Haptics.light()
            model.session.sendInput([
                .key(usage: usage, down: true, mods: activeMods),
                .key(usage: usage, down: false, mods: activeMods)
            ])
        } label: {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .frame(minWidth: 48, minHeight: 44)
                .padding(.horizontal, 8)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Numpad & Media Area

    private var numpadAndMediaArea: some View {
        HStack(alignment: .top, spacing: 16) {
            // Numpad 4x4
            VStack(spacing: 8) {
                Text("Bàn phím số").font(.caption).foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 8) {
                    keyButton("7", usage: 0x5F)
                    keyButton("8", usage: 0x60)
                    keyButton("9", usage: 0x61)
                    keyButton("/", usage: 0x54)
                }
                HStack(spacing: 8) {
                    keyButton("4", usage: 0x5C)
                    keyButton("5", usage: 0x5D)
                    keyButton("6", usage: 0x5E)
                    keyButton("*", usage: 0x55)
                }
                HStack(spacing: 8) {
                    keyButton("1", usage: 0x59)
                    keyButton("2", usage: 0x5A)
                    keyButton("3", usage: 0x5B)
                    keyButton("-", usage: 0x56)
                }
                HStack(spacing: 8) {
                    keyButton("0", usage: 0x62)
                    keyButton(".", usage: 0x63)
                    keyButton("=", usage: 0x58)
                    keyButton("+", usage: 0x57)
                }
            }

            Divider().background(Color.white.opacity(0.15)).frame(height: 240)

            // Điều khiển Media & Presentation
            VStack(spacing: 12) {
                Text("Thuyết trình & Media").font(.caption).foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 8) {
                    mediaButton("Trình chiếu (F5)", systemName: "play.rectangle.fill", usage: 0x3E)
                    mediaButton("Thoát (Esc)", systemName: "xmark.rectangle", usage: 0x29)
                }
                HStack(spacing: 8) {
                    mediaButton("Slide trước", systemName: "chevron.left.circle.fill", usage: 0x4B) // Page Up
                    mediaButton("Slide kế", systemName: "chevron.right.circle.fill", usage: 0x4E) // Page Down
                }
                HStack(spacing: 8) {
                    mediaButton("Space", systemName: "space", usage: 0x2C)
                    mediaButton("Hoàn tác", systemName: "arrow.uturn.backward", usage: 0x1D, mods: .command)
                }
            }
        }
        .padding(16)
    }

    private func mediaButton(_ label: String, systemName: String, usage: UInt16, mods: InputModifiers = []) -> some View {
        Button {
            Haptics.light()
            model.session.sendInput([
                .key(usage: usage, down: true, mods: mods),
                .key(usage: usage, down: false, mods: mods)
            ])
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 20))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
