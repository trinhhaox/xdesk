import SwiftUI
import UIKit
import XdeskMedia
import XdeskViewer
import XdeskWire

/// Toàn màn hình: video letterbox trên nền đen, ẩn status bar + home indicator, nút thoát mờ + nút bàn phím ở góc trên.
struct StreamView: View {
    let model: StreamViewModel
    @Environment(\.displayScale) private var displayScale
    @State private var composing = false
    @State private var composer: TextComposerController?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black
                VideoSurface(renderer: model.session.renderer, session: model.session, config: model.currentConfig)
                if model.session.state != .streaming {
                    connectingOverlay
                }
                topBar
            }
            .onChange(of: proxy.size, initial: true) { _, size in
                model.screenChanged(ScreenMetrics(size: size, scale: displayScale))
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .alert("Agent AI xin quyền điều khiển", isPresented: approvalPresented, presenting: model.session.pendingAgentApproval) { _ in
            Button("Cho phép") { Task { await model.session.answerAgentApproval(allow: true) } }
            Button("Từ chối", role: .cancel) { Task { await model.session.answerAgentApproval(allow: false) } }
        } message: { request in
            Text("\(request.agentName): \(request.summary)\nChỉ cho phép nếu chính bạn vừa yêu cầu agent làm việc trên Mac.")
        }
    }

    /// Hộp thoại hiện khi host có yêu cầu và tự tắt khi hết hạn; việc đóng do nút bấm xử lý nên setter không làm gì.
    private var approvalPresented: Binding<Bool> {
        Binding(get: { model.session.pendingAgentApproval != nil }, set: { _ in })
    }

    @ViewBuilder private var connectingOverlay: some View {
        Group {
            if model.isPairing { SasView(code: model.sasCode) } else { ProgressView("Đang kết nối…").tint(.white).foregroundStyle(.white) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            Button { Task { await model.disconnect() } } label: { faintIcon("xmark.circle.fill") }
                .accessibilityLabel("Ngắt kết nối")
            if composing, let composer {
                TextComposerBar(controller: composer) { composing = false }
                    .padding(.trailing, 16)
            } else {
                Button { openComposer() } label: { faintIcon("keyboard") }
                    .accessibilityLabel("Mở bàn phím gõ chữ")
                    .disabled(model.session.state != .streaming)
            }
        }
    }

    private func faintIcon(_ name: String) -> some View {
        Image(systemName: name).font(.title).foregroundStyle(.white.opacity(0.5)).padding(16)
    }

    private func openComposer() {
        composer = TextComposerController(session: model.session)
        composing = true
    }
}

/// Cầu nối `AVSampleBufferDisplayLayer` của `VideoLayerRenderer` + lớp nhập liệu cảm ứng vào SwiftUI.
private struct VideoSurface: UIViewRepresentable {
    let renderer: VideoLayerRenderer
    let session: ViewerSession
    let config: DisplayConfig?

    func makeUIView(context: Context) -> VideoHostView {
        VideoHostView(videoLayer: renderer.layer, touchView: TouchInputView(session: session, renderer: renderer))
    }

    func updateUIView(_ view: VideoHostView, context: Context) {
        guard let config, config.scale > 0 else { return }
        view.touchView.hostPoints = CGSize(width: Double(config.w) / config.scale, height: Double(config.h) / config.scale)
    }
}

private final class VideoHostView: UIView {
    private let videoLayer: CALayer
    let touchView: TouchInputView

    init(videoLayer: CALayer, touchView: TouchInputView) {
        self.videoLayer = videoLayer
        self.touchView = touchView
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(videoLayer)
        addSubview(touchView)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        CATransaction.commit()
        touchView.frame = bounds
    }
}
