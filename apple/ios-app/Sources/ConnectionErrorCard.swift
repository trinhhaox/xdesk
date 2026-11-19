import SwiftUI

/// Thẻ lỗi kết nối trên danh sách máy: biểu tượng, câu mô tả, gợi ý, nút hành động và "Chi tiết" (thông báo kỹ thuật).
struct ConnectionErrorCard: View {
    let failure: ConnectionFailure
    let onAction: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: failure.symbol)
                    .font(.title3)
                    .foregroundStyle(BrandPalette.danger)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(failure.title).font(.headline)
                    if let hint = failure.hint { Text(hint).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Đóng thông báo lỗi")
            }
            Button(action: onAction) {
                Label(failure.action == .retry ? "Thử lại" : "Ghép đôi", systemImage: failure.action == .retry ? "arrow.clockwise" : "link")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandPalette.primaryFill)
            if let detail = failure.detail {
                DisclosureGroup("Chi tiết") {
                    Text(detail)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
