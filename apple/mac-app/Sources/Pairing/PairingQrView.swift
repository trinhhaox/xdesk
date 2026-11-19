import SwiftUI
import XdeskTransport

/// Nội dung cửa sổ "Ghép đôi thiết bị mới": QR + dấu vân tay của Mac + đồng hồ đếm ngược.
struct PairingQrView: View {
    let coordinator: PairingCoordinator

    var body: some View {
        VStack(spacing: 14) {
            Text("Ghép đôi thiết bị mới").font(.title3.bold())
            content
            if let fingerprint = coordinator.security.identityFingerprint {
                VStack(spacing: 2) {
                    Text("Dấu vân tay của Mac này").font(.caption).foregroundStyle(.secondary)
                    Text(fingerprint).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    @ViewBuilder private var content: some View {
        if let message = coordinator.availability.blockedMessage {
            notice(message, symbol: "eye.slash", tint: BrandPalette.warning)
        } else if let uri = coordinator.security.qrURI, let issuedAt = coordinator.qrIssuedAt {
            qr(uri.string, issuedAt: issuedAt)
        } else if coordinator.justPaired {
            notice("Đã ghép đôi xong. Thiết bị mới có thể kết nối tới Mac này.", symbol: "checkmark.circle.fill", tint: BrandPalette.accent)
            Button("Ghép thêm thiết bị") { Task { await coordinator.refreshQr() } }
        } else {
            notice("Mã QR đã hết hạn. Tạo mã mới rồi quét lại bằng Xdesk trên điện thoại.", symbol: "clock.badge.exclamationmark", tint: BrandPalette.warning)
            Button("Tạo mã mới") { Task { await coordinator.refreshQr() } }
                .buttonStyle(.borderedProminent).tint(BrandPalette.primary)
        }
    }

    private func qr(_ text: String, issuedAt: Date) -> some View {
        VStack(spacing: 10) {
            if let image = QrImage.make(text, side: 240) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 240, height: 240)
                    .padding(10).background(.white, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Mã QR ghép đôi")
            } else {
                notice("Không tạo được ảnh mã QR.", symbol: "exclamationmark.triangle", tint: BrandPalette.warning)
            }
            Text("Mở Xdesk trên điện thoại, chọn \"Quét mã QR trên Mac\" rồi quét mã này.")
                .font(.callout).lineLimit(3).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = PairingCountdown.remaining(issuedAt: issuedAt, now: context.date)
                Text("Mã hết hạn sau \(PairingCountdown.label(seconds: seconds))")
                    .font(.callout.monospacedDigit()).foregroundStyle(seconds <= 20 ? BrandPalette.warning : .secondary)
            }
            Button("Tạo mã mới") { Task { await coordinator.refreshQr() } }
        }
    }

    private func notice(_ message: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(tint)
            Text(message).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}
