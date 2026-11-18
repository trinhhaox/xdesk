import SwiftUI
import UIKit
import XdeskMedia

/// Toàn màn hình: video letterbox trên nền đen, ẩn status bar + home indicator, nút thoát mờ ở góc.
struct StreamView: View {
    let model: StreamViewModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black
                VideoSurface(renderer: model.session.renderer)
                if model.session.state != .streaming {
                    ProgressView("Đang kết nối…").tint(.white).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                closeButton
            }
            .onChange(of: proxy.size, initial: true) { _, size in
                model.screenChanged(ScreenMetrics(size: size, scale: displayScale))
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private var closeButton: some View {
        Button { Task { await model.disconnect() } } label: {
            Image(systemName: "xmark.circle.fill").font(.title).foregroundStyle(.white.opacity(0.5)).padding(16)
        }
        .accessibilityLabel("Ngắt kết nối")
    }
}

/// Cầu nối `AVSampleBufferDisplayLayer` của `VideoLayerRenderer` vào SwiftUI.
private struct VideoSurface: UIViewRepresentable {
    let renderer: VideoLayerRenderer

    func makeUIView(context: Context) -> VideoHostView { VideoHostView(videoLayer: renderer.layer) }
    func updateUIView(_ view: VideoHostView, context: Context) {}
}

private final class VideoHostView: UIView {
    private let videoLayer: CALayer

    init(videoLayer: CALayer) {
        self.videoLayer = videoLayer
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(videoLayer)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
    }
}
