import SwiftUI

private extension View {
    func cardBackground() -> some View {
        background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// Thẻ quyền: mỗi quyền thiếu một dòng với nút "Mở Cài đặt".
struct PermissionCard: View {
    let missing: [PermissionKind]
    let open: (PermissionKind) -> Void
    var relaunch: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Cần cấp quyền", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.multicolor)
                .padding(.bottom, 8)
            ForEach(missing) { kind in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.title).font(.callout.weight(.medium))
                        Text(kind.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Button("Mở Cài đặt") { open(kind) }
                        .controlSize(.small)
                        .accessibilityLabel("Mở Cài đặt để cấp quyền \(kind.title)")
                }
                .padding(.vertical, 6)
                if kind == .screenRecording {
                    Button("Đã bật rồi? Mở lại Xdesk để áp dụng", action: relaunch)
                        .buttonStyle(.link).font(.caption).padding(.bottom, 6)
                }
                if kind != missing.last { Divider() }
            }
        }
        .padding(12)
        .background(BrandPalette.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(BrandPalette.warning.opacity(0.5)))
    }
}

struct NoticeRow: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Thiết bị đang xem": viewer đang xem, mỗi dòng có nút gửi tệp và ngắt kết nối.
struct SessionsCard: View {
    let sessions: [PopoverState.Session]
    let disconnect: (UUID) -> Void
    var sendFile: (UUID) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Thiết bị đang xem (\(sessions.count))").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            if sessions.isEmpty {
                Text("Chưa có thiết bị nào đang xem.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { session in
                    HStack(spacing: 10) {
                        Image(systemName: session.info.transport.symbol)
                            .frame(width: 26, height: 26)
                            .background(BrandPalette.accent.opacity(0.18), in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.info.name).font(.callout.weight(.medium)).lineLimit(1)
                            Text("\(session.info.modeLabel) · \(session.info.transport.label)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                        Spacer(minLength: 6)
                        Button { sendFile(session.id) } label: {
                            Image(systemName: "arrow.up.doc").font(.callout).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Gửi tệp tới \(session.info.name)…")
                        .accessibilityLabel("Gửi tệp tới \(session.info.name)")
                        Button { disconnect(session.id) } label: {
                            Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Ngắt kết nối \(session.info.name)")
                        .accessibilityLabel("Ngắt kết nối \(session.info.name)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardBackground()
    }
}

/// Hàng hành động lớn, bấm được cả hàng. Tiêu đề kết thúc bằng "…" (mở cửa sổ) nên không thêm mũi tên ">".
struct ActionRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white)
                    .frame(width: 28, height: 28)
                    .background(BrandPalette.primaryStrong, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text(title).font(.body)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
    }
}

struct HoverRowStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : (hovering ? 0.07 : 0)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovering = $0 }
    }
}

/// Dòng trạng thái gọn các kênh: LAN, Tailscale, USB.
struct ChannelsCard: View {
    let state: PopoverState
    let connectUsb: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            line("wifi", state.lanText.map { String(localized: "LAN \($0)") } ?? String(localized: "LAN: chưa có địa chỉ"))
            line("network", state.tailscaleText)
            if state.usb.isEmpty {
                line("cable.connector", String(localized: "USB: chưa cắm thiết bị"))
            } else {
                ForEach(state.usb) { device in
                    HStack(spacing: 6) {
                        line("cable.connector", String(localized: "USB …\(device.label)"))
                        Spacer(minLength: 4)
                        Button("Phát qua USB") { connectUsb(device.id) }
                            .controlSize(.small).disabled(!state.isHosting)
                            .accessibilityLabel("Phát qua USB tới thiết bị …\(device.label)")
                    }
                }
            }
            if let message = state.usbMessage { line("exclamationmark.circle", String(localized: "USB: \(message)")) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .cardBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kênh kết nối")
    }

    private func line(_ symbol: String, _ text: String) -> some View {
        // Chữ dùng màu nhãn chính (đủ tương phản trên nền kính); chỉ biểu tượng dùng màu phụ.
        Label {
            Text(verbatim: text).foregroundStyle(.primary).textSelection(.enabled)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
        }
        .font(.caption).lineLimit(1)
    }
}

struct PopoverFooter: View {
    let state: PopoverState
    let actions: PopoverActions

    var body: some View {
        HStack(spacing: 14) {
            footerButton("gearshape", String(localized: "Cài đặt…"), actions.openSettings).keyboardShortcut(",")
            footerButton("arrow.triangle.2.circlepath", state.updateVersion.map { String(localized: "Cập nhật \($0)…") } ?? String(localized: "Kiểm tra cập nhật…"), actions.checkForUpdates)
                .disabled(!state.canCheckUpdates)
            Spacer(minLength: 0)
            footerButton("power", String(localized: "Thoát"), actions.quit).keyboardShortcut("q")
        }
    }

    private func footerButton(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.caption).labelStyle(.titleAndIcon) }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.primary)
    }
}
