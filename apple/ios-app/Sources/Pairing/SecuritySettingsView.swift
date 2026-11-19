import SwiftUI
import XdeskCrypto

/// Cài đặt bảo mật: dấu vân tay của thiết bị này và các máy Mac đã ghép (quên máy).
struct SecuritySettingsView: View {
    let model: StreamViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var forgetting: PairedDevice?

    var body: some View {
        NavigationStack {
            Form {
                Section("Thiết bị này") {
                    if let fingerprint = model.ownFingerprint {
                        LabeledContent("Dấu vân tay") { Text(fingerprint).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }
                    }
                    if let error = model.securityError {
                        Label("Không mở được kho khoá bảo mật: \(error). Chưa thể ghép đôi.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                Section("Máy Mac đã ghép") {
                    if model.knownHosts.isEmpty { Text("Chưa ghép với máy nào.").foregroundStyle(.secondary) }
                    ForEach(model.knownHosts, id: \.id) { host in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.name)
                            Text(host.id).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        .swipeActions { Button("Quên", role: .destructive) { forgetting = host } }
                    }
                }
            }
            .navigationTitle("Bảo mật")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Xong") { dismiss() } }
            .task { await model.refreshTrust() }
            .confirmationDialog(
                "Quên \"\(forgetting?.name ?? "")\"?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
                titleVisibility: .visible, presenting: forgetting
            ) { host in
                Button("Quên máy này", role: .destructive) { Task { await model.forgetHost(id: host.id) } }
            } message: { _ in
                Text("Lần sau bạn phải ghép đôi lại với máy này.")
            }
        }
    }
}
