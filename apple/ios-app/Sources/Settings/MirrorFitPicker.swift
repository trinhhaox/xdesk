import SwiftUI
import XdeskInput
import XdeskWire

extension MirrorFit {
    var title: String {
        switch self {
        case .native: "Giống màn hình Mac"
        case .fitDevice: "Vừa với điện thoại"
        case .touch: "Tối ưu thao tác"
        }
    }

    var summary: String {
        switch self {
        case .native: "Giữ nguyên Mac, xem cả màn hình rồi phóng to bằng hai ngón."
        case .fitDevice: "Mac đổi theo kích thước và chiều xoay của điện thoại."
        case .touch: "Như Vừa với điện thoại nhưng nút và chữ to hơn, dễ chạm."
        }
    }

    var symbol: String {
        switch self {
        case .native: "macbook"
        case .fitDevice: "iphone.gen3"
        case .touch: "hand.point.up.left"
        }
    }
}

/// Chọn kiểu vừa khung của Bản sao ở danh sách máy Mac: mỗi lựa chọn kèm một dòng giải thích.
/// Chọn "Tối ưu thao tác" thì gợi ý (không ép) dùng chế độ chuột Chạm trực tiếp.
struct MirrorFitPicker: View {
    @Binding var fit: MirrorFit
    let pointer: PointerSettingsStore

    var body: some View {
        Section {
            ForEach(MirrorFit.allCases, id: \.self) { option in
                let selected = fit == option
                Button {
                    Haptics.light()
                    fit = option
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.symbol)
                            .font(.title3)
                            .foregroundStyle(BrandPalette.primary)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title)
                                .foregroundStyle(.primary)
                            Text(option.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(BrandPalette.primary)
                        }
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            if fit == .touch, pointer.settings.mode != .direct {
                Button("Gợi ý: dùng chế độ chuột \(PointerMode.direct.title)") { pointer.settings.mode = .direct }
                    .font(.footnote)
            }
        } header: {
            Text("Kiểu chiếu màn hình")
        }
    }
}

/// Dòng trong menu nút nổi của màn stream: mở danh sách 3 kiểu chiếu ngay trong panel và hiển thị rõ tên chế độ đang chọn.
struct MirrorFitMenu: View {
    @Binding var fit: MirrorFit
    @Binding var expanded: Bool
    let onToggle: () -> Void
    let onSelectDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.light()
                onToggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: fit.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 22, alignment: .center)
                    Text("Kiểu chiếu: \(fit.title)")
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kiểu chiếu màn hình")
            .accessibilityValue(fit.title)
            .accessibilityHint(expanded ? "Thu gọn danh sách kiểu chiếu" : "Mở danh sách 3 kiểu chiếu để chọn")

            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(MirrorFit.allCases, id: \.self) { option in
                        let selected = option == fit
                        Button {
                            Haptics.light()
                            if fit != option {
                                fit = option
                            }
                            onSelectDone()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: option.symbol)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(selected ? BrandPalette.primaryOnOverlay : .white.opacity(0.75))
                                    .frame(width: 20, alignment: .center)
                                Text(option.title)
                                    .font(.subheadline.weight(selected ? .semibold : .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Spacer(minLength: 4)
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(BrandPalette.primaryOnOverlay)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                            .padding(.horizontal, 10)
                            .background(
                                selected ? BrandPalette.primaryFill.opacity(0.22) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.title)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
    }
}
