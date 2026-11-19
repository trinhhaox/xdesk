import SwiftUI
import XdeskCrypto

/// Cửa sổ "Thiết bị đã ghép": danh tính Mac, cảnh báo bảo mật, viewer được phép vào máy này, host đã ghép (khi Mac này là viewer).
struct PairedDevicesSettings: View {
    let security: SecurityCenter
    @State private var revoking: PairedDevice?

    var body: some View {
        Form {
            Section("Mac này") {
                if let fingerprint = security.identityFingerprint {
                    LabeledContent("Dấu vân tay") {
                        Text(fingerprint).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }
                }
                if let error = security.startupError {
                    warning("Không mở được kho khoá bảo mật: \(error). Ghép đôi và kết nối mã hoá đang tắt.", tint: .red)
                }
                if security.keychainWarning {
                    warning("Khoá của Mac nằm ở chùm khoá đăng nhập cũ nên kém an toàn hơn. Hãy cài bản Xdesk đã ký đầy đủ rồi ghép đôi lại.", tint: BrandPalette.warning)
                }
                if security.integrityNotice {
                    VStack(alignment: .leading, spacing: 6) {
                        warning("Danh sách thiết bị từng bị sửa hoặc hỏng nên Xdesk đã bỏ đi và tạo danh sách trống. Hãy ghép đôi lại các thiết bị của bạn.", tint: BrandPalette.warning)
                        Button("Đã hiểu") { Task { await security.acknowledgeIntegrityNotice() } }
                    }
                }
            }
            Section("Thiết bị được phép kết nối vào Mac này") {
                if security.pairedViewers.isEmpty {
                    Text("Chưa có thiết bị nào. Chọn \"Ghép đôi thiết bị mới…\" trong menu Xdesk.").foregroundStyle(.secondary)
                }
                ForEach(security.pairedViewers, id: \.id) { device in
                    PairedViewerRow(device: device, security: security) { revoking = device }
                }
            }
            Section("Máy Mac đã ghép (để xem từ máy này)") {
                if security.knownHosts.isEmpty { Text("Chưa có máy nào.").foregroundStyle(.secondary) }
                ForEach(security.knownHosts, id: \.id) { host in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(host.name)
                            Text(host.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Quên máy này", role: .destructive) { Task { await security.forgetHost(deviceId: host.id) } }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .task { await security.refresh() }
        .confirmationDialog(
            "Thu hồi \"\(revoking?.name ?? "")\"?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
            presenting: revoking
        ) { device in
            Button("Thu hồi", role: .destructive) { Task { await security.revoke(deviceId: device.id) } }
        } message: { _ in
            Text("Thiết bị sẽ bị ngắt ngay và phải ghép đôi lại để kết nối.")
        }
    }

    private func warning(_ text: String, tint: Color) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill").foregroundStyle(tint).fixedSize(horizontal: false, vertical: true)
    }
}
