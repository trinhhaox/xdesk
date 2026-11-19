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
            Picker("Kiểu bản sao", selection: $fit) {
                ForEach(MirrorFit.allCases, id: \.self) { option in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(option.title, systemImage: option.symbol)
                        Text(option.summary).font(.footnote).foregroundStyle(.secondary)
                    }
                    .tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            if fit == .touch, pointer.settings.mode != .direct {
                Button("Gợi ý: dùng chế độ chuột \(PointerMode.direct.title)") { pointer.settings.mode = .direct }
                    .font(.footnote)
            }
        } header: {
            Text("Kiểu bản sao")
        }
    }
}

/// Dòng trong menu nút nổi của màn stream: đổi kiểu vừa khung giữa phiên (host sẽ mở lại màn hình theo `display.config` mới).
struct MirrorFitMenu: View {
    @Binding var fit: MirrorFit

    var body: some View {
        Menu {
            Picker("Kiểu bản sao", selection: $fit) {
                ForEach(MirrorFit.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
        } label: {
            Label("Kiểu: \(fit.title)", systemImage: fit.symbol).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 10)
        }
        .accessibilityLabel("Kiểu bản sao")
        .accessibilityValue(fit.title)
    }
}
