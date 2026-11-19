import SwiftUI
import UIKit
import XdeskInput
import XdeskMedia
import XdeskViewer
import XdeskWire

/// Toàn màn hình: video letterbox trên nền đen, ẩn status bar + home indicator, thanh nút mờ (thoát, clipboard, bàn phím, chế độ chuột, cài đặt) ở góc trên.
struct StreamView: View {
    let model: StreamViewModel
    @Environment(\.displayScale) private var displayScale
    @State private var composer: TextComposerController
    @State private var pointer = PointerSettingsStore()
    @State private var showPointerSettings = false
    @State private var modeNotice: String?

    init(model: StreamViewModel) {
        self.model = model
        _composer = State(initialValue: TextComposerController(session: model.session))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black
                VideoSurface(
                    renderer: model.session.renderer, session: model.session, config: model.currentConfig,
                    composer: composer, pointer: pointer.settings
                )
                if model.session.state != .streaming {
                    connectingOverlay
                }
                topBar
                if !composer.preview.isEmpty { composingPreview }
                if let notice = modeNotice ?? model.clipboardNotice { toast(notice) }
            }
            .onChange(of: proxy.size, initial: true) { _, size in
                model.screenChanged(ScreenMetrics(size: size, scale: displayScale))
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showPointerSettings) { PointerSettingsSheet(store: pointer) }
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
            if model.session.clipboardAvailable {
                Button { Task { await model.sendClipboardToMac() } } label: { faintIcon("doc.on.clipboard") }
                    .accessibilityLabel("Gửi clipboard sang Mac")
            }
            Button { composer.isActive.toggle() } label: { faintIcon(composer.isActive ? "keyboard.fill" : "keyboard") }
                .accessibilityLabel(composer.isActive ? "Ẩn bàn phím" : "Mở bàn phím gõ chữ")
                .disabled(model.session.state != .streaming)
            Button { toggleMode() } label: { faintIcon(pointer.settings.mode.symbol) }
                .accessibilityLabel("Đổi chế độ chuột")
                .accessibilityValue(pointer.settings.mode.title)
            Button { showPointerSettings = true } label: { faintIcon("slider.horizontal.3") }
                .accessibilityLabel("Cài đặt chuột và con trỏ")
        }
    }

    /// Chữ Telex đang soạn: chỉ xem trước nhỏ ngay trên bàn phím, chữ chốt mới gửi sang Mac.
    private var composingPreview: some View {
        Text(composer.preview)
            .font(.callout)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.black.opacity(0.75), in: Capsule())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, composer.obscuredHeight + 8)
            .allowsHitTesting(false)
            .accessibilityLabel("Đang soạn: \(composer.preview)")
    }

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.black.opacity(0.7), in: Capsule())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 40 + composer.obscuredHeight)
            .allowsHitTesting(false)
    }

    private func faintIcon(_ name: String) -> some View {
        Image(systemName: name).font(.title).foregroundStyle(.white.opacity(0.5)).padding(16)
    }

    private func toggleMode() {
        pointer.toggleMode()
        modeNotice = "Chế độ chuột: \(pointer.settings.mode.title)"
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            modeNotice = nil
        }
    }
}

/// Cầu nối `AVSampleBufferDisplayLayer` của `VideoLayerRenderer` + lớp nhập liệu cảm ứng vào SwiftUI.
private struct VideoSurface: UIViewRepresentable {
    let renderer: VideoLayerRenderer
    let session: ViewerSession
    let config: DisplayConfig?
    let composer: TextComposerController
    let pointer: PointerSettings

    func makeUIView(context: Context) -> VideoHostView {
        VideoHostView(videoLayer: renderer.layer, touchView: TouchInputView(session: session, renderer: renderer), controller: composer)
    }

    func updateUIView(_ view: VideoHostView, context: Context) {
        view.touchView.pointer = pointer
        view.syncKeyboard(active: composer.isActive)
        guard let config, config.scale > 0 else { return }
        view.touchView.hostPoints = CGSize(width: Double(config.w) / config.scale, height: Double(config.h) / config.scale)
    }
}
