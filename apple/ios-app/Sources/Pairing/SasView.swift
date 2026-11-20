import SwiftUI
import XdeskTransport

/// Phủ lên màn hình stream trong lúc ghép đôi: mã 6 số để so với Mac, hoặc trạng thái chờ xác nhận.
/// Hai phía đều phải bấm "Khớp": iPhone không tin máy nào tự nhận là Mac nếu người dùng chưa so mã.
/// Cỡ chữ theo Dynamic Type; ở cỡ lớn nhất thẻ cuộn được thay vì tràn khỏi màn hình.
struct SasView: View {
    let prompt: SasPrompt?
    @State private var confirmedCode: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let prompt {
                    Text(prompt.code)
                        .font(.largeTitle.bold().monospaced())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(BrandPalette.primaryOnOverlay)
                        .accessibilityLabel("Mã ghép đôi \(prompt.code.map(String.init).joined(separator: " "))")
                    if confirmedCode == prompt.code {
                        Text("Trên Mac, bấm \"Khớp, cho phép\".").multilineTextAlignment(.center)
                        waiting
                    } else {
                        Text("So với mã trên Mac. Chỉ bấm \"Khớp\" khi hai mã giống hệt nhau.").multilineTextAlignment(.center)
                        answerButtons(prompt)
                    }
                } else {
                    waiting
                }
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

    private var waiting: some View {
        VStack(spacing: 14) {
            ProgressView().tint(.white)
            Text("Đang chờ Mac xác nhận…").font(.headline)
        }
    }

    private func answerButtons(_ prompt: SasPrompt) -> some View {
        HStack(spacing: 12) {
            Button("Không khớp", role: .destructive) { prompt.answer(false) }
                .buttonStyle(.bordered)
            Button("Khớp") {
                confirmedCode = prompt.code
                prompt.answer(true)
            }
            .buttonStyle(.borderedProminent).tint(BrandPalette.primaryFill)
        }
        .controlSize(.large)
    }
}
