import SwiftUI
import UIKit
import XdeskInput
import XdeskMedia
import XdeskViewer
import XdeskWire

/// Video letterbox trong vùng an toàn (không dưới tai thỏ/Dynamic Island) trên nền đen; mọi điều khiển gom vào một nút nổi
/// kéo được (không che menu bar Mac).
struct StreamView: View {
    let model: StreamViewModel
    @Environment(\.displayScale) private var displayScale
    @State private var composer: TextComposerController
    @State private var pointer = PointerSettingsStore()
    @State private var showPointerSettings = false
    @State private var modeNotice: String?
    @State private var zoom = VideoZoomState()
    @State private var floating = FloatingControlStore()

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
                    composer: composer, pointer: pointer.settings, zoom: zoom
                )
                if model.session.state != .streaming {
                    connectingOverlay
                }
                FloatingControl(store: floating, container: floatingArea(proxy.size)) { close in menuItems(close) }
                if !composer.preview.isEmpty { composingPreview }
                if let notice = modeNotice ?? model.clipboardNotice { toast(notice) }
            }
            .onChange(of: proxy.size, initial: true) { _, size in
                model.screenChanged(ScreenMetrics(size: size, scale: displayScale))
            }
        }
        .ignoresSafeArea(.keyboard)
        .background(Color.black.ignoresSafeArea())
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

    /// Vùng nút nổi được di chuyển: bàn phím không làm đổi cỡ vùng stream (`ignoresSafeArea(.keyboard)`, nếu đổi sẽ phải xin lại cấu hình
    /// với host) nên tự trừ phần bàn phím che; nhờ vậy nút nổi và menu vẫn thấy được khi gõ.
    private func floatingArea(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: max(FloatingControl<EmptyView>.buttonSize, size.height - composer.obscuredHeight))
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

    private func menuItems(_ close: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            item("Ngắt kết nối", "xmark.circle", close) { Task { await model.disconnect() } }
            item(composer.isActive ? "Ẩn bàn phím" : "Bàn phím", composer.isActive ? "keyboard.fill" : "keyboard", close) { composer.isActive.toggle() }
                .disabled(model.session.state != .streaming)
            item("Chuột: \(pointer.settings.mode.title)", pointer.settings.mode.symbol, close) { toggleMode() }
            item("Cài đặt chuột", "slider.horizontal.3", close) { showPointerSettings = true }
            if model.session.clipboardAvailable {
                item("Gửi clipboard sang Mac", "doc.on.clipboard", close) { Task { await model.sendClipboardToMac() } }
            }
            if model.screenMode == .mirror { MirrorFitMenu(fit: mirrorFit) }
            if zoom.isZoomed { item("Vừa khung màn hình", "arrow.down.right.and.arrow.up.left", close) { zoom.reset?() } }
        }
    }

    private func item(_ title: String, _ symbol: String, _ close: @escaping () -> Void, action: @escaping () -> Void) -> some View {
        Button { action(); close() } label: {
            Label(title, systemImage: symbol)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
    }

    private var mirrorFit: Binding<MirrorFit> {
        Binding(get: { model.mirrorFit }, set: { model.mirrorFit = $0 })
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
    let zoom: VideoZoomState

    func makeUIView(context: Context) -> VideoHostView {
        VideoHostView(videoLayer: renderer.layer, touchView: TouchInputView(session: session, renderer: renderer), controller: composer, zoomState: zoom)
    }

    func updateUIView(_ view: VideoHostView, context: Context) {
        view.touchView.pointer = pointer
        view.syncKeyboard(active: composer.isActive)
        view.zoomEnabled = config?.isNativeMirror ?? false
        guard let config, config.scale > 0 else { return }
        view.touchView.hostPoints = CGSize(width: Double(config.w) / config.scale, height: Double(config.h) / config.scale)
    }
}
