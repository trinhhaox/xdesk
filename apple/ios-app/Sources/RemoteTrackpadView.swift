import SwiftUI
import UIKit

/// Màn hình điều khiển: biến iPhone/iPad thành Chuột cảm ứng, Bàn phím ảo và Trình chiếu & Phím số điều khiển Mac từ xa.
/// Một thanh trên gọn (menu 5 chế độ) + nội dung chiếm toàn bộ phần còn lại, bố cục tính từ kích thước thật của vùng.
struct RemoteTrackpadView: View {
    let model: StreamViewModel

    @State private var cursor = TrackpadCursor()

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            VStack(spacing: 0) {
                ControlTopBar(model: model, isLandscape: isLandscape)
                Divider().background(Color.white.opacity(0.15))
                content(isLandscape: isLandscape)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Xoay giữa lúc đang giữ phím: nhả hết trước khi dựng lại bố cục.
            .onChange(of: isLandscape) { model.macKeyboard.releaseAll() }
        }
        .background(BrandPalette.overlaySurface.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func content(isLandscape: Bool) -> some View {
        switch model.activeWorkMode {
        case .trackpad: TrackpadModeView(model: model, cursor: cursor, isLandscape: isLandscape)
        case .keyboard: KeyboardPanel(model: model, cursor: cursor)
        case .numpadMedia: SlideNumpadView(model: model)
        case .mirror, .extend: EmptyView()
        }
    }
}
