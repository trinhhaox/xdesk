import SwiftUI

/// Nút chọn chế độ làm việc dạng menu thả xuống (biểu tượng + tên chế độ hiện tại ▾) thay cho lưới 5 nút.
struct WorkModeMenu: View {
    let activeMode: WorkMode
    let height: CGFloat
    let onSelect: (WorkMode) -> Void

    var body: some View {
        Menu {
            ForEach(WorkMode.allCases) { mode in
                Button {
                    Haptics.light()
                    onSelect(mode)
                } label: {
                    if mode == activeMode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Label(mode.title, systemImage: mode.symbol)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: activeMode.symbol).font(.system(size: 13, weight: .semibold))
                Text(activeMode.shortTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(BrandPalette.primaryFill, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Chế độ: \(activeMode.title)")
    }
}
