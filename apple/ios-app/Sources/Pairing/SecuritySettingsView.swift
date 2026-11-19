import SwiftUI
import XdeskCrypto

/// Bảo mật (đẩy vào màn Cài đặt): dấu vân tay của thiết bị này và các máy Mac đã ghép (quên máy).
struct SecuritySettingsView: View {
    let model: StreamViewModel
    @State private var forgetting: PairedDevice?

    var body: some View {
            Form {
                Section("Thiết bị này") {
                    if let fingerprint = model.ownFingerprint {
                        LabeledContent("Dấu vân tay") { Text(fingerprint).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }
                    }
                    if let error = model.securityError {
                        Label("Không mở được kho khoá bảo mật: \(error). Chưa thể ghép đôi.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(BrandPalette.danger)
                    }
                }
                Section("Máy Mac đã ghép") {
                    if model.knownHosts.isEmpty { Text("Chưa ghép với máy nào.").foregroundStyle(.secondary) }
                    ForEach(model.knownHosts, id: \.id) { host in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.name)
                            Text(host.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        .swipeActions { Button("Xoá", role: .destructive) { forgetting = host } }
                    }
                }
            }
            .navigationTitle("Bảo mật")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.refreshTrust() }
            .forgetHostDialog($forgetting, model: model)
    }
}
