import SwiftUI

/// Bộ chọn nhanh 5 chế độ làm việc dạng lưới 2+3 gọn gàng:
/// - Hàng 1: Chiếu Mac | Màn phụ
/// - Hàng 2: Chuột | Bàn phím | Slide & Số
struct WorkModeSwitcher: View {
    let activeMode: WorkMode
    let onSelect: (WorkMode) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                pill(.mirror)
                pill(.extend)
            }
            HStack(spacing: 6) {
                pill(.trackpad)
                pill(.keyboard)
                pill(.numpadMedia)
            }
        }
    }

    private func pill(_ mode: WorkMode) -> some View {
        let selected = activeMode == mode
        return Button {
            Haptics.light()
            onSelect(mode)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(mode.shortTitle)
                    .font(.system(size: 11, weight: selected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(selected ? BrandPalette.primaryFill : BrandPalette.overlayKey, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(selected ? .white : .white.opacity(0.85))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(mode.title)
    }
}
