import SwiftUI

/// Phủ lên màn hình stream trong lúc ghép đôi: mã 6 số để so với Mac, hoặc trạng thái chờ xác nhận.
struct SasView: View {
    let code: String?

    var body: some View {
        VStack(spacing: 14) {
            if let code {
                Text(code).font(.system(size: 52, weight: .bold, design: .monospaced)).foregroundStyle(BrandPalette.primary)
                Text("Trên Mac, kiểm tra cùng mã này rồi bấm \"Khớp, cho phép\".").multilineTextAlignment(.center)
            }
            ProgressView().tint(.white)
            Text("Đang chờ Mac xác nhận…").font(.headline)
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: 360)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
    }
}
