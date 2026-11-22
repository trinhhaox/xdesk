import LocalAuthentication
import SwiftUI
import UIKit
import XdeskInput
import XdeskMedia
import XdeskTransport
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
    @State private var showFileImporter = false
    @State private var shortcutsExpanded = false
    @State private var fitExpanded = false
    @State private var displaysExpanded = false
    @State private var modeNotice: String?
    @State private var noticeTask: Task<Void, Never>?
    @State private var zoom = VideoZoomState()
    @State private var floating = FloatingControlStore()

    init(model: StreamViewModel) {
        self.model = model
        _composer = State(initialValue: TextComposerController(session: model.session))
    }

    var body: some View {
        ZStack {
            if model.activeWorkMode.isControlMode {
                RemoteTrackpadView(model: model)
            } else {
                streamContent
            }
            if model.session.state != .streaming {
                connectingOverlay
            }
        }
    }

    private var streamContent: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black
                VideoSurface(
                    renderer: model.session.renderer, session: model.session, config: model.currentConfig,
                    composer: composer, pointer: pointer.settings, zoom: zoom
                )
                FloatingControl(
                    store: floating,
                    container: floatingArea(proxy.size),
                    onCollapse: { shortcutsExpanded = false; fitExpanded = false; displaysExpanded = false }
                ) { close, keepAlive in
                    menuItems(close, keepAlive: keepAlive)
                }
                if !composer.preview.isEmpty { composingPreview }
                if let help = model.session.pendingAgentHelp { agentHelpBanner(help) }
                VStack(spacing: 8) {
                    if let transfer = model.session.activeFileTransfer {
                        fileTransferBanner(transfer)
                    }
                    if let fileURL = model.session.lastReceivedFileURL {
                        receivedFileBanner(fileURL)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                if let notice = modeNotice ?? model.clipboardNotice { toast(notice) }
            }
            .onChange(of: proxy.size, initial: true) { _, size in
                model.screenChanged(ScreenMetrics(size: size, scale: displayScale, maxFps: ScreenMetrics.currentMaxFps()))
            }
        }
        .ignoresSafeArea(.keyboard)
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showPointerSettings) { PointerSettingsSheet(store: pointer) }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                guard url.startAccessingSecurityScopedResource() else { return }
                Task {
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        try await model.session.sendFile(url: url)
                        showTransientNotice("Đã gửi tệp \(url.lastPathComponent) sang Mac")
                    } catch is CancellationError {
                        showTransientNotice("Đã huỷ gửi tệp")
                    } catch {
                        showTransientNotice("Gửi tệp thất bại: \(error.localizedDescription)")
                    }
                }
            }
        }
        .onChange(of: model.session.lastUnlockResult) { _, result in
            guard let result else { return }
            showTransientNotice(result.message)
            model.session.clearLastUnlockResult()
        }
        .onChange(of: model.session.lastFileTransferError) { _, err in
            guard let err else { return }
            showTransientNotice("Nhận tệp thất bại: \(err)")
            model.session.clearLastFileTransferError()
        }
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
            if model.isPairing { SasView(prompt: model.sasPrompt) } else { connectingCard }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.75).ignoresSafeArea())
    }

    /// Từ lúc chạm máy Mac tới khung hình đầu tiên: tên máy, vòng quay và nút Huỷ quay về danh sách.
    private var connectingCard: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large).tint(.white)
            Text(
                model.reconnectAttempt > 0
                    ? "Đang kết nối lại tới \(model.connectingName ?? "máy Mac") (lần \(model.reconnectAttempt)/3)…"
                    : "Đang kết nối tới \(model.connectingName ?? "máy Mac")…"
            )
                .font(.headline).multilineTextAlignment(.center)
            Button { Task { await model.disconnect() } } label: {
                Text("Huỷ").frame(minWidth: 120, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: 360)
        .background(BrandPalette.overlaySurface.opacity(0.9), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }

    private func menuItems(_ close: @escaping () -> Void, keepAlive: @escaping () -> Void) -> some View {
        let dismiss = {
            shortcutsExpanded = false
            fitExpanded = false
            displaysExpanded = false
            close()
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Chế độ làm việc")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
            WorkModeSwitcher(activeMode: model.activeWorkMode) { mode in
                model.switchWorkMode(to: mode)
                dismiss()
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 6)
            quickDockRow(dismiss)
            Divider().background(Color.white.opacity(0.2)).padding(.vertical, 4)
            HStack(spacing: 4) {
                Button {
                    Haptics.light()
                    toggleMode()
                    dismiss()
                } label: {
                    Label("Chuột: \(pointer.settings.mode.title)", systemImage: pointer.settings.mode.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.leading, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.light()
                    showPointerSettings = true
                    dismiss()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cài đặt chuột và con trỏ")
            }
            if model.session.audioAvailable {
                item(
                    model.session.audioMuted ? "Âm thanh: Đã tắt" : "Âm thanh: Bật",
                    model.session.audioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    dismiss
                ) {
                    model.session.toggleAudioMute()
                    showTransientNotice(model.session.audioMuted ? "Đã tắt tiếng trên thiết bị" : "Đã bật tiếng")
                }
            }
            if model.activeWorkMode == .mirror {
                MirrorFitMenu(
                    fit: mirrorFit,
                    expanded: $fitExpanded,
                    onToggle: {
                        fitExpanded.toggle()
                        if fitExpanded { shortcutsExpanded = false; displaysExpanded = false }
                        keepAlive()
                    },
                    onSelectDone: dismiss
                )
                if model.session.hostDisplays.count >= 2 {
                    hostDisplayPickerMenu(dismiss: dismiss, keepAlive: keepAlive)
                }
            }
            if zoom.isZoomed { item("Vừa khung màn hình", "arrow.down.right.and.arrow.up.left", dismiss) { zoom.reset?() } }
            Button {
                Haptics.light()
                shortcutsExpanded.toggle()
                if shortcutsExpanded { fitExpanded = false; displaysExpanded = false }
                keepAlive()
            } label: {
                HStack {
                    Label("Phím tắt Mac", systemImage: "square.2.layers.3d.top.filled")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .rotationEffect(.degrees(shortcutsExpanded ? 90 : 0))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if shortcutsExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    shortcutItem("Spotlight (⌘ Space)", "magnifyingglass", dismiss) { sendShortcut(usage: 0x2C, mods: .command) }
                    shortcutItem("Mission Control (⌃ ↑)", "square.2.layers.3d.top.filled", dismiss) { sendShortcut(usage: 0x52, mods: .control) }
                    shortcutItem("Chuyển app (⌘ Tab)", "app.dashed", dismiss) { sendShortcut(usage: 0x2B, mods: .command) }
                    shortcutItem("Hoàn tác (⌘ Z)", "arrow.uturn.backward", dismiss) { sendShortcut(usage: 0x1D, mods: .command) }
                    shortcutItem("Mở khoá Mac", "faceid", dismiss) { unlockMacWithBiometrics() }
                }
                .padding(.leading, 10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
            if model.session.clipboardAvailable {
                item("Gửi clipboard sang Mac", "doc.on.clipboard", dismiss) { Task { await model.sendClipboardToMac() } }
            }
            if model.session.supportsFileTransfer {
                item("Gửi tệp sang Mac…", "arrow.up.doc", dismiss) { showFileImporter = true }
            }
            Divider().background(Color.white.opacity(0.2)).padding(.vertical, 4)
            item("Ngắt kết nối", "xmark.circle", dismiss, tint: BrandPalette.danger) { Task { await model.disconnect() } }
        }
    }

    private func quickDockRow(_ close: @escaping () -> Void) -> some View {
        let keyboardEnabled = model.session.state == .streaming
        return HStack(spacing: 4) {
            dockTile(
                systemName: composer.isActive ? "keyboard.fill" : "keyboard",
                label: composer.isActive ? "Ẩn phím" : "Bàn phím",
                accessibility: composer.isActive ? "Ẩn bàn phím" : "Hiện bàn phím",
                enabled: keyboardEnabled
            ) {
                composer.isActive.toggle()
                close()
            }
            dockTile(systemName: "lock.fill", label: "Khoá Mac", accessibility: "Khóa máy Mac") {
                Task { await model.session.sendSystemLock() }
                close()
            }
            dockTile(systemName: "camera.viewfinder", label: "Chụp ảnh", accessibility: "Chụp ảnh màn hình Mac") {
                sendShortcut(usage: 0x21, mods: [.command, .shift])
                close()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.vertical, 2)
    }

    private func dockTile(systemName: String, label: String, accessibility: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(enabled ? 0.12 : 0.05)))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.45))
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(accessibility)
    }

    private func sendShortcut(usage: UInt16, mods: InputModifiers) {
        model.session.sendInput([
            .key(usage: usage, down: true, mods: mods),
            .key(usage: usage, down: false, mods: mods)
        ])
    }

    private func item(_ title: String, _ symbol: String, _ close: @escaping () -> Void, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button { Haptics.light(); action(); close() } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shortcutItem(_ title: String, _ symbol: String, _ close: @escaping () -> Void, action: @escaping () -> Void) -> some View {
        Button { Haptics.light(); action(); close() } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
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
            .background(BrandPalette.overlaySurface.opacity(0.85), in: Capsule())
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
            .background(BrandPalette.overlaySurface.opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
    }

    private var mirrorFit: Binding<MirrorFit> {
        Binding(get: { model.mirrorFit }, set: { model.mirrorFit = $0 })
    }

    private func toggleMode() {
        pointer.toggleMode()
        showTransientNotice("Chế độ chuột: \(pointer.settings.mode.title)")
    }

    private func showTransientNotice(_ message: String) {
        noticeTask?.cancel()
        modeNotice = message
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            modeNotice = nil
        }
    }

    private func unlockMacWithBiometrics() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            showTransientNotice("Cần bật Face ID / mật mã điện thoại để mở khoá Mac")
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Xác thực để mở khóa máy Mac") { success, _ in
            Task { @MainActor in
                if success {
                    await model.session.sendSystemUnlock()
                } else {
                    showTransientNotice("Đã huỷ xác thực mở khoá Mac")
                }
            }
        }
    }

    @ViewBuilder
    private func hostDisplayPickerMenu(dismiss: @escaping () -> Void, keepAlive: @escaping () -> Void) -> some View {
        let activeId = model.selectedDisplayId ?? model.session.hostDisplays.first(where: \.isMain)?.id ?? model.session.hostDisplays.first?.id
        let activeName = model.session.hostDisplays.first(where: { $0.id == activeId })?.name ?? "Mặc định"
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.light()
                displaysExpanded.toggle()
                if displaysExpanded { fitExpanded = false; shortcutsExpanded = false }
                keepAlive()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "display.2")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 22, alignment: .center)
                    Text("Màn hình: \(activeName)")
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .rotationEffect(.degrees(displaysExpanded ? 90 : 0))
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if displaysExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.session.hostDisplays) { display in
                        let selected = display.id == activeId
                        Button {
                            Haptics.light()
                            model.selectedDisplayId = display.id
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Text("\(display.name) (\(display.width)×\(display.height))")
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
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            .padding(.horizontal, 10)
                            .background(
                                selected ? BrandPalette.primaryFill.opacity(0.22) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
            }
        }
    }

    private func fileTransferBanner(_ progress: FileTransferProgress) -> some View {
        let percent = Int((progress.fraction * 100).rounded())
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(progress.direction == .sending ? "Đang gửi" : "Đang nhận") \(progress.fileName) (\(percent)%)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                ProgressView(value: progress.fraction)
                    .tint(BrandPalette.primaryOnOverlay)
            }
            Button("Huỷ") {
                Task { await model.session.cancelFileTransfer() }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.18), in: Capsule())
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(BrandPalette.overlaySurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func receivedFileBanner(_ url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .foregroundStyle(BrandPalette.accent)
            Text("Đã nhận \(url.lastPathComponent)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            ShareLink(item: url) {
                Text("Chia sẻ")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(BrandPalette.primaryFill, in: Capsule())
                    .foregroundStyle(.white)
            }
            Button {
                model.session.clearLastReceivedFile()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(BrandPalette.overlaySurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func agentHelpBanner(_ help: ViewerSession.AgentHelpNotice) -> some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BrandPalette.warning)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent AI cần trợ giúp:")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text(help.reason)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }
                Spacer()
                Button("Đã xong") {
                    Task { await model.session.resolveAgentHelp() }
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(BrandPalette.accent)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .padding(12)
            .background(BrandPalette.overlaySurface.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
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
