import SwiftUI
import XdeskTransport
import XdeskViewer

/// "Thêm & kết nối khác" / "Cách kết nối khác": Quét QR (khi đã có máy), "Nhập địa chỉ" (LAN/Tailscale) và "Cáp USB".
struct OtherConnectionsSection: View {
    let model: StreamViewModel
    @Binding var manualText: String
    var onScanQr: (() -> Void)? = nil
    let tailscaleState: TailscaleState
    let onTailscaleAction: () -> Void
    let onConnect: () -> Void
    @State private var tailscaleOpen = false
    @State private var addressOpen = false
    @State private var usbOpen = false

    static func normalizedAddress(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!t.isEmpty && !t.contains(":") && !t.hasSuffix("]")) ? "\(t):47800" : t
    }

    var body: some View {
        Section(onScanQr != nil ? "Thêm & kết nối khác" : "Cách kết nối khác") {
            if let onScanQr {
                Button(action: onScanQr) {
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title3)
                            .foregroundStyle(BrandPalette.primary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Quét mã QR để ghép đôi").foregroundStyle(.primary)
                            Text("Trên Mac: menu Xdesk → Ghép đôi thiết bị mới…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            DisclosureGroup(isExpanded: $tailscaleOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tailscaleState.detailDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if tailscaleState == .active {
                        HStack(spacing: 8) {
                            Button {
                                Haptics.light()
                                addressOpen = true
                            } label: {
                                Text("Nhập địa chỉ Tailscale")
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(BrandPalette.primaryFill)
                            .buttonBorderShape(.capsule)
                            Button {
                                Haptics.light()
                                onTailscaleAction()
                            } label: {
                                Text("Mở Tailscale")
                                    .frame(minHeight: 40)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        }
                    } else {
                        Button {
                            Haptics.light()
                            onTailscaleAction()
                        } label: {
                            Text(tailscaleState.actionLabel)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BrandPalette.primaryFill)
                        .buttonBorderShape(.capsule)
                    }
                }
                .padding(.vertical, 4)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .foregroundStyle(tailscaleState == .active ? BrandPalette.accent : BrandPalette.warning)
                        .frame(width: 24)
                    Text("Tailscale (Kết nối từ xa)")
                    Spacer(minLength: 8)
                    Text(tailscaleState.statusBadge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tailscaleState == .active ? BrandPalette.accent : BrandPalette.warning)
                }
            }
            DisclosureGroup(isExpanded: $addressOpen) {
                TextField("192.168.1.10:47800 hoặc 100.x.y.z", text: $manualText)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(onConnect)
                    .frame(minHeight: 44)
                Button("Kết nối", action: onConnect).disabled(ViewerTarget.parse(manual: Self.normalizedAddress(manualText)) == nil)
                Button("Lưu máy này") { Task { if await model.addManualHost(address: manualText) { manualText = "" } } }
                    .disabled(ManualHostAddress(manualText) == nil)
                if let error = model.manualHostError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(BrandPalette.danger).font(.footnote)
                }
                if tailscaleState != .active {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "network.badge.shield.half.filled")
                                .foregroundStyle(BrandPalette.warning)
                                .accessibilityHidden(true)
                            Text(tailscaleState.inlineHint)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            Haptics.light()
                            onTailscaleAction()
                        } label: {
                            Text(tailscaleState.actionLabel)
                                .frame(maxWidth: .infinity, minHeight: 42)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BrandPalette.primaryFill)
                        .buttonBorderShape(.capsule)
                    }
                    .padding(.vertical, 4)
                }
                Text("Qua Tailscale: nhập IP 100.x.y.z hoặc tên máy (MagicDNS) của Mac, rồi \"Lưu máy này\". Trên Mac phải bật \"Cho phép kết nối qua Tailscale\".")
                    .font(.footnote).foregroundStyle(.secondary)
            } label: {
                Label("Nhập địa chỉ", systemImage: "globe")
            }
            DisclosureGroup(isExpanded: $usbOpen) {
                Text("Cắm cáp vào Mac rồi chọn \"Phát qua USB\" trong menu Xdesk trên Mac. Cần đã ghép đôi với Mac này qua Wi-Fi trước.")
                    .font(.footnote).foregroundStyle(.secondary)
            } label: {
                Label("Cáp USB", systemImage: "cable.connector")
            }
        }
        .onChange(of: model.manualHostError) { _, error in
            if error != nil { addressOpen = true }
        }
    }
}
