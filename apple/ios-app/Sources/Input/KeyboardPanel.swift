import SwiftUI
import XdeskInput

/// Hai kiểu bàn phím ảo; lựa chọn được nhớ giữa các lần mở và đổi bằng nút gạt trên thanh trên.
enum KeyboardPanelMode: String, CaseIterable, Identifiable {
    case macKeyboard
    case textInput

    static let storageKey = "keyboardPanelMode"

    var id: String { rawValue }
    var title: String { self == .macKeyboard ? "Bàn phím Mac" : "Gõ văn bản" }
    var symbol: String { self == .macKeyboard ? "keyboard" : "textformat" }
    var toggled: KeyboardPanelMode { self == .macKeyboard ? .textInput : .macKeyboard }
}

/// Nội dung chế độ "Bàn phím ảo", chiếm toàn bộ vùng còn lại và nhả hết phím khi đổi hướng / rời chế độ.
/// Ngang: bàn phím Mac tràn rộng. Dọc: vùng di chuột ở trên, bàn phím Mac đầy đủ ở dưới.
struct KeyboardPanel: View {
    let model: StreamViewModel
    let cursor: TrackpadCursor

    @AppStorage(KeyboardPanelMode.storageKey) private var modeRaw = KeyboardPanelMode.macKeyboard.rawValue
    @Environment(\.scenePhase) private var scenePhase
    private var keyboard: MacKeyboardModel { model.macKeyboard }
    private var mode: KeyboardPanelMode { KeyboardPanelMode(rawValue: modeRaw) ?? .macKeyboard }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            Group {
                switch mode {
                case .macKeyboard: macKeyboard(size: proxy.size)
                case .textInput: TextInputPanel(model: model, isLandscape: isLandscape)
                }
            }
            .onChange(of: isLandscape) { keyboard.releaseAll() }
        }
        .onAppear { keyboard.send = { model.session.sendInput($0) } }
        .onChange(of: modeRaw) { keyboard.releaseAll() }
        .onChange(of: model.session.state) { if model.session.state != .streaming { keyboard.releaseAll() } }
        .onChange(of: scenePhase) { if scenePhase != .active { keyboard.releaseAll() } }
        .onDisappear { keyboard.releaseAll() }
    }

    private func macKeyboard(size: CGSize) -> some View {
        let inner = CGSize(width: size.width - 8, height: size.height)
        let plan = KeyboardScreenPlan(size: inner)
        return VStack(spacing: 0) {
            if let pad = plan.pad {
                TrackpadPad(model: model, cursor: cursor, mods: keyboard.controller.activeMods, showsHint: false)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .frame(height: pad.height)
            }
            MacKeyboardView(keyboard: keyboard, minKeyHeight: plan.minKeyHeight, showsBubble: plan.pad != nil)
                .frame(height: plan.keyboard.height)
        }
        .padding(.horizontal, 4)
        .frame(width: size.width, height: size.height)
    }
}
