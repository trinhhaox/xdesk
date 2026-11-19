import SwiftUI

/// Phủ lên màn hình stream trong lúc ghép đôi: mã 6 số để so với Mac, hoặc trạng thái chờ xác nhận.
/// Cỡ chữ theo Dynamic Type; ở cỡ lớn nhất thẻ cuộn được thay vì tràn khỏi màn hình.
struct SasView: View {
    let code: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let code {
                    Text(code)
                        .font(.largeTitle.bold().monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(BrandPalette.primaryOnOverlay)
                        .accessibilityLabel("Mã ghép đôi \(code.map(String.init).joined(separator: " "))")
                    Text("Trên Mac, kiểm tra cùng mã này rồi bấm \"Khớp, cho phép\".").multilineTextAlignment(.center)
                }
                ProgressView().tint(.white)
                Text("Đang chờ Mac xác nhận…").font(.headline)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(BrandPalette.overlaySurface.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
    }
}
