import AppKit
import SwiftUI

/// Nội dung popover thanh menu: đầu trang + nút chia sẻ, thẻ quyền (nếu thiếu), viewer đang xem, hành động, kênh kết nối, chân trang.
struct MenuPopoverView: View {
    static let width: CGFloat = 340
    let state: PopoverState
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PopoverHeader(state: state, toggle: actions.toggleSharing)
            if !state.missing.isEmpty { PermissionCard(missing: state.missing, open: actions.openPermission, relaunch: actions.relaunch) }
            if state.secureInput { NoticeRow(symbol: "lock.fill", text: String(localized: "Đang bật nhập liệu bảo mật: chữ gõ từ xa có thể không vào ô mật khẩu.")) }
            SessionsCard(sessions: state.sessions, disconnect: actions.disconnect)
            VStack(spacing: 4) {
                ActionRow(symbol: "qrcode", title: "Ghép đôi thiết bị mới…", action: actions.pairNewDevice)
                ActionRow(symbol: "ipad.and.iphone", title: "Thiết bị đã ghép…", action: actions.showPairedDevices)
                ActionRow(symbol: "laptopcomputer.and.arrow.down", title: "Kết nối tới máy khác…", action: actions.connectToMac)
            }
            ChannelsCard(state: state, connectUsb: actions.connectUsb)
            Divider()
            PopoverFooter(state: state, actions: actions)
        }
        .padding(14)
        .frame(width: Self.width)
    }
}

private struct PopoverHeader: View {
    let state: PopoverState
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Dùng đúng biểu tượng app để đồng nhất với Dock, Finder và hộp thoại hệ thống.
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 38, height: 38)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Xdesk").font(.headline)
                        if let version = state.version { Text(version).font(.caption).foregroundStyle(.secondary) }
                    }
                    StatusPillView(pill: state.pill)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Xdesk, \(state.pill.title)")
            if let message = state.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button(action: toggle) {
                Label(state.isHosting ? String(localized: "Dừng chia sẻ") : String(localized: "Bắt đầu chia sẻ"), systemImage: state.isHosting ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BigButtonStyle(kind: state.isHosting ? .destructive : .primary))
            .accessibilityHint(state.isHosting ? String(localized: "Ngắt mọi thiết bị đang xem") : String(localized: "Cho phép thiết bị đã ghép nhìn thấy Mac này"))
        }
    }
}

struct StatusPillView: View {
    let pill: StatusPill

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 8, height: 8)
            // Chữ dùng màu nhãn hệ thống để luôn đạt tương phản; màu thương hiệu chỉ nằm ở chấm và nền nhạt.
            Text(pill.title).font(.caption.weight(.semibold)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(dot.opacity(0.18), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trạng thái: \(pill.title)")
    }

    private var dot: Color {
        switch pill {
        case .sharing: BrandPalette.accent
        case .stopped: Color.secondary
        case .needsPermission: BrandPalette.warning
        case .failed: Color.red
        }
    }
}

struct BigButtonStyle: ButtonStyle {
    /// `.destructive` dùng cho "Dừng chia sẻ": tông đỏ nhạt để không trông như nút bị vô hiệu hoá.
    enum Kind { case primary, destructive }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(kind == .primary ? Color.white : Color.red)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(kind == .primary ? BrandPalette.primaryStrong : Color.red.opacity(0.14))
                    .opacity(configuration.isPressed ? 0.75 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
