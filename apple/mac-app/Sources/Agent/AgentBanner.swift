import AppKit
import Observation
import SwiftUI
import XdeskAgent

@MainActor
@Observable
final class AgentBannerModel {
    var control = ControlSnapshot()
}

/// Dải luôn nằm trên cùng màn hình agent: cho người thấy ai đang điều khiển và Tạm dừng/Tiếp tục/Dừng.
/// Không nhận focus (panel không kích hoạt) để không cướp phím của app agent đang dùng.
/// Cửa sổ đăng ký vào `SecureWindowRegistry` nên bị loại khỏi ảnh chụp của agent và luồng stream.
@MainActor
final class AgentBanner {
    private static let size = NSSize(width: 360, height: 40)
    private let model = AgentBannerModel()
    private var panel: NSPanel?
    private var registeredID: CGWindowID?
    private let onPause: () -> Void
    private let onResume: () -> Void
    private let onStop: () -> Void

    init(onPause: @escaping () -> Void, onResume: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.onPause = onPause; self.onResume = onResume; self.onStop = onStop
    }

    /// Khung banner theo toạ độ CG (gốc trên-trái) để monitor bỏ qua cú bấm của người vào banner.
    var cgFrame: CGRect? {
        guard let panel, panel.isVisible, let primary = NSScreen.screens.first else { return nil }
        let frame = panel.frame
        return CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    func update(_ control: ControlSnapshot, displayID: CGDirectDisplayID?) {
        model.control = control
        switch control.phase {
        case .granted, .paused:
            if let displayID { show(on: displayID) }
        case .none, .requested:
            hide()
        }
    }

    func hide() {
        if let registeredID { SecureWindowRegistry.shared.remove(registeredID) }
        registeredID = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func show(on displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID })
        else { return }
        let origin = NSPoint(x: screen.frame.midX - Self.size.width / 2, y: screen.visibleFrame.maxY - Self.size.height - 6)
        if let panel {
            panel.setFrameOrigin(origin)
            return
        }
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.sharingType = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: AgentBannerView(model: model, onPause: onPause, onResume: onResume, onStop: onStop))
        panel.orderFrontRegardless()
        let id = CGWindowID(panel.windowNumber)
        SecureWindowRegistry.shared.insert(id)
        registeredID = id
        self.panel = panel
    }
}

private struct AgentBannerView: View {
    let model: AgentBannerModel
    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void

    var body: some View {
        let paused = model.control.phase == .paused
        let holderName = model.control.holder ?? String(localized: "Agent AI")
        HStack(spacing: 10) {
            Circle().fill(paused ? Color.orange : Color.green).frame(width: 10, height: 10)
            Text(paused ? String(localized: "Agent đã tạm dừng") : String(localized: "\(holderName) đang điều khiển"))
                .font(.system(size: 13, weight: .medium)).lineLimit(1)
            Spacer(minLength: 4)
            Button(paused ? String(localized: "Tiếp tục") : String(localized: "Tạm dừng")) { paused ? onResume() : onPause() }
            Button("Dừng", role: .destructive, action: onStop)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(width: 360, height: 40)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(paused ? Color.orange : Color.green, lineWidth: 1.5))
    }
}
