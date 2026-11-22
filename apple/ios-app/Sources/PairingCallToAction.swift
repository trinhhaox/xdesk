import SwiftUI

/// Màn trống khi chưa ghép với Mac nào: hướng dẫn + quét QR là hành động chính, mã 6 số / nhập địa chỉ là phụ.
struct EmptyPairingState: View {
    let action: () -> Void

    var body: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "desktopcomputer").font(.system(size: 44)).foregroundStyle(BrandPalette.primary).accessibilityHidden(true)
                Text("Chưa ghép với máy Mac nào").font(.title3.bold()).multilineTextAlignment(.center)
                Text("Trên Mac: menu Xdesk → Ghép đôi thiết bị mới…, rồi quét mã QR hiện trên Mac.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(action: action) {
                    Label("Quét mã QR để ghép đôi", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent).tint(BrandPalette.primaryFill).controlSize(.large)
                Text("Không quét được? Chọn một máy Mac trong mục \"Máy Mac khác trên mạng\" để so mã 6 số, hoặc nhập địa chỉ ở \"Cách kết nối khác\".")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }
}
