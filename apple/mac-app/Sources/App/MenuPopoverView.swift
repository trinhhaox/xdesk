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
            if state.secureInput { NoticeRow(symbol: "lock.fill", text: "Đang bật nhập liệu bảo mật: chữ gõ từ xa có thể không vào ô mật khẩu.") }
            SessionsCard(sessions: state.sessions, disconnect: actions.disconnect)
            VStack(spacing: 4) {
                ActionRow(symbol: "qrcode", title: "Ghép đôi thiết bị mới…", prominent: true, action: actions.pairNewDevice)
                ActionRow(symbol: "ipad.and.iphone", title: "Thiết bị đã ghép…", prominent: true, action: actions.showPairedDevices)
                ActionRow(symbol: "laptopcomputer.and.arrow.down", title: "Kết nối tới máy khác…", prominent: false, action: actions.connectToMac)
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
                Image(systemName: "display.2")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(BrandPalette.primaryStrong, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Xdesk").font(.headline)
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
                Label(state.isHosting ? "Dừng chia sẻ" : "Bắt đầu chia sẻ", systemImage: state.isHosting ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BigButtonStyle(filled: !state.isHosting))
            .accessibilityHint(state.isHosting ? "Ngắt mọi thiết bị đang xem" : "Cho phép thiết bị đã ghép nhìn thấy Mac này")
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
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(filled ? Color.white : Color.primary)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(filled ? BrandPalette.primaryStrong : Color.primary.opacity(0.1))
                    .opacity(configuration.isPressed ? 0.75 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
