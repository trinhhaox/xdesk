import SwiftUI
import XdeskCrypto
import XdeskTransport

/// Hộp thoại "‹tên› muốn ghép đôi": QR (xác nhận + chọn quyền) hoặc so mã 6 số. Đóng cửa sổ = từ chối.
struct SasConfirmView: View {
    let request: PairingRequest
    let onDecision: (PairingDecision) -> Void
    @State private var draft = ApprovalDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("\(request.deviceName) muốn ghép đôi", systemImage: "link.badge.plus").font(.title3.bold())
            Text("Cách ghép: \(request.method.title) · \(request.deviceId)").font(.caption).foregroundStyle(.secondary)
            if case .sas(let code) = request.method {
                VStack(spacing: 6) {
                    Text(code).font(.system(size: 44, weight: .bold, design: .monospaced)).foregroundStyle(BrandPalette.primary)
                    Text("Mã có khớp với màn hình kia không?").font(.callout)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                Text("Thiết bị này vừa quét mã QR của bạn. Chỉ cho phép nếu đó là thiết bị của bạn.").font(.callout)
            }
            permissions
            HStack {
                Button(rejectTitle, role: .cancel) { onDecision(.reject) }
                Spacer()
                Button(approveTitle) { onDecision(.approve(draft.permissions)) }
                    .buttonStyle(.borderedProminent).tint(BrandPalette.primary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 380)
    }

    private var permissions: some View {
        GroupBox("Quyền cho thiết bị này") {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Xem màn hình", isOn: .constant(true)).disabled(true)
                Toggle("Điều khiển (chuột, bàn phím)", isOn: $draft.input)
                Toggle("Clipboard", isOn: $draft.clipboard)
                Toggle("Âm thanh", isOn: $draft.audio)
                Toggle("Gửi/nhận tệp", isOn: $draft.fileTransfer)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }

    private var approveTitle: String {
        if case .sas = request.method { String(localized: "Khớp, cho phép") } else { String(localized: "Cho phép") }
    }

    private var rejectTitle: String {
        if case .sas = request.method { String(localized: "Không khớp") } else { String(localized: "Từ chối") }
    }
}
