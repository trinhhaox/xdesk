import SwiftUI
import XdeskTransport
import XdeskViewer

/// "Thêm & kết nối khác" / "Cách kết nối khác": Quét QR (khi đã có máy), "Nhập địa chỉ" (LAN/Tailscale) và "Cáp USB".
struct OtherConnectionsSection: View {
    let model: StreamViewModel
    @Binding var manualText: String
    var onScanQr: (() -> Void)? = nil
    let onConnect: () -> Void
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
                Text("Qua Tailscale: nhập IP 100.x.y.z hoặc tên máy (MagicDNS) của Mac, rồi \"Lưu máy này\". Trên Mac phải bật \"Cho phép kết nối qua Tailscale\".")
                    .font(.footnote).foregroundStyle(.secondary)
            } label: {
                Label("Nhập địa chỉ", systemImage: "network")
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
