import SwiftUI
import XdeskTransport
import XdeskViewer

/// "Nhập địa chỉ" (LAN/Tailscale) và "Cáp USB": thu gọn mặc định để danh sách máy Mac luôn ở đầu màn hình.
struct OtherConnectionsSection: View {
    let model: StreamViewModel
    @Binding var manualText: String
    let onConnect: () -> Void
    @State private var addressOpen = false
    @State private var usbOpen = false

    var body: some View {
        Section("Cách kết nối khác") {
            DisclosureGroup(isExpanded: $addressOpen) {
                TextField("192.168.1.10:47800 hoặc 100.x.y.z", text: $manualText)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(onConnect)
                    .frame(minHeight: 44)
                Button("Kết nối", action: onConnect).disabled(ViewerTarget.parse(manual: manualText) == nil)
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
