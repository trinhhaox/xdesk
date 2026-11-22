import SwiftUI
import UIKit
import XdeskInput
import XdeskViewer
import XdeskWire

/// Màn hình điều khiển: biến iPhone/iPad thành Chuột cảm ứng, Bàn phím ảo và Trình chiếu & Phím số điều khiển Mac từ xa,
/// với thanh chuyển nhanh thống nhất 5 chế độ làm việc ngay ở đầu màn hình.
struct RemoteTrackpadView: View {
    let model: StreamViewModel

    @State private var cursorX: Float = 0.5
    @State private var cursorY: Float = 0.5
    @State private var activeMods: InputModifiers = []
    @State private var inputText: String = ""
    @State private var isLeftDown = false
    @State private var isRightDown = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(Color.white.opacity(0.15))

            switch model.activeWorkMode {
            case .trackpad:
                trackpadArea
            case .keyboard:
                keyboardArea
            case .numpadMedia:
                numpadAndMediaArea
            case .mirror, .extend:
                EmptyView()
            }
        }
        .background(BrandPalette.overlaySurface.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Header Bar (Tên máy Mac + Bộ chọn 5 chế độ 2+3 thống nhất)

    private var headerBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(model.connectingName ?? "Điều khiển Mac")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 2) {
                    Button {
                        Haptics.light()
                        Task { await model.session.sendSystemLock() }
                    } label: {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Khóa Mac")

                    Button {
                        Haptics.light()
                        Task { await model.disconnect() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(BrandPalette.danger)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ngắt kết nối")
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            WorkModeSwitcher(activeMode: model.activeWorkMode) { mode in
                model.switchWorkMode(to: mode)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - 1. Trackpad Area

    private var trackpadArea: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(BrandPalette.overlayCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )

                VStack(spacing: 6) {
                    Image(systemName: "computermouse.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.38))
                    Text("Bàn di chuột cảm ứng")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                    Text("1 ngón: Di chuột · Chạm đúp giữ: Kéo thả\n2 ngón: Chuột phải / Cuộn · 3 ngón: Không gian & Cửa sổ")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.horizontal, 16)
                .allowsHitTesting(false)

                TrackpadTouchSurface(
                    onMove: { dx, dy in moveCursor(dx: dx, dy: dy) },
                    onLeftClick: { sendLeftClick() },
                    onRightClick: { sendRightClick() },
                    onScroll: { dx, dy in sendScroll(dx: dx, dy: dy) },
                    onDragStateChange: { dragging in
                        isLeftDown = dragging
                        model.session.sendInput([
                            .button(down: dragging, button: InputButton.left, x: cursorX, y: cursorY, mods: activeMods)
                        ])
                    },
                    onThreeFingerShortcut: { usage, mods in
                        Haptics.light()
                        model.session.sendInput([
                            .key(usage: usage, down: true, mods: mods),
                            .key(usage: usage, down: false, mods: mods)
                        ])
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            HStack(spacing: 12) {
                Button {
                    sendLeftClick()
                } label: {
                    Text("Chuột Trái")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(isLeftDown ? BrandPalette.primaryFill : BrandPalette.overlayKey, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isLeftDown = true }
                        .onEnded { _ in isLeftDown = false }
                )

                Button {
                    sendRightClick()
                } label: {
                    Text("Chuột Phải")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(isRightDown ? BrandPalette.primaryFill : BrandPalette.overlayKey, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isRightDown = true }
                        .onEnded { _ in isRightDown = false }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func moveCursor(dx: Float, dy: Float) {
        cursorX = min(0.999, max(0.001, cursorX + dx))
        cursorY = min(0.999, max(0.001, cursorY + dy))
        model.session.sendInput([.move(x: cursorX, y: cursorY, mods: activeMods)])
    }

    private func sendScroll(dx: Float, dy: Float) {
        model.session.sendInput([.scroll(dx: dx, dy: dy, mods: activeMods)])
    }

    private func sendLeftClick() {
        Haptics.light()
        model.session.sendInput([
            .button(down: true, button: InputButton.left, x: cursorX, y: cursorY, mods: activeMods),
            .button(down: false, button: InputButton.left, x: cursorX, y: cursorY, mods: activeMods)
        ])
    }

    private func sendRightClick() {
        Haptics.light()
        model.session.sendInput([
            .button(down: true, button: InputButton.right, x: cursorX, y: cursorY, mods: activeMods),
            .button(down: false, button: InputButton.right, x: cursorX, y: cursorY, mods: activeMods)
        ])
    }

    // MARK: - 2. Keyboard Area

    private var keyboardArea: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Khung gõ text tiếng Việt gửi sang Mac
                HStack(spacing: 8) {
                    TextField(
                        "Nhập tiếng Việt / văn bản sang Mac…",
                        text: $inputText,
                        prompt: Text("Nhập tiếng Việt / văn bản sang Mac…").foregroundStyle(.white.opacity(0.45))
                    )
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(BrandPalette.overlayCard, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .foregroundStyle(.white)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit { sendTypedText() }

                    Button("Gửi") { sendTypedText() }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(inputText.isEmpty ? BrandPalette.overlayKey : BrandPalette.primaryFill, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(inputText.isEmpty ? .white.opacity(0.45) : .white)
                        .disabled(inputText.isEmpty)
                }
                .padding(.top, 12)

                // Thanh phím bổ trợ Modifier (⌘ ⌥ ⌃ ⇧)
                HStack(spacing: 8) {
                    modToggle("⌘ Cmd", .command)
                    modToggle("⌥ Opt", .option)
                    modToggle("⌃ Ctrl", .control)
                    modToggle("⇧ Shift", .shift)
                }

                // Hàng phím tiện ích
                HStack(spacing: 8) {
                    keyButton("Esc", usage: 0x29)
                    keyButton("Tab", usage: 0x2B)
                    keyButton("Space", usage: 0x2C)
                    keyButton("⌫ Del", usage: 0x2A)
                    keyButton("↩ Enter", usage: 0x28)
                }

                // Phím tắt hay dùng + Cụm phím mũi tên
                HStack(spacing: 8) {
                    keyButton("⌘ C", usage: 0x06, extraMods: .command)
                    keyButton("⌘ V", usage: 0x19, extraMods: .command)
                    keyButton("⌘ A", usage: 0x04, extraMods: .command)
                }

                VStack(spacing: 8) {
                    keyButton("↑", usage: 0x52, fillWidth: false)
                    HStack(spacing: 8) {
                        keyButton("←", usage: 0x50, fillWidth: false)
                        keyButton("↓", usage: 0x51, fillWidth: false)
                        keyButton("→", usage: 0x4F, fillWidth: false)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func sendTypedText() {
        guard !inputText.isEmpty else { return }
        let textToSend = inputText
        inputText = ""
        Task {
            _ = await model.session.sendText(textToSend)
        }
    }

    private func modToggle(_ label: String, _ mod: InputModifiers) -> some View {
        let active = activeMods.contains(mod)
        return Button {
            Haptics.light()
            if active {
                activeMods.remove(mod)
            } else {
                activeMods.insert(mod)
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(active ? BrandPalette.primaryFill : BrandPalette.overlayKey, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func keyButton(_ label: String, usage: UInt16, extraMods: InputModifiers = [], fillWidth: Bool = true) -> some View {
        let mods = activeMods.union(extraMods)
        return Button {
            Haptics.light()
            model.session.sendInput([
                .key(usage: usage, down: true, mods: mods),
                .key(usage: usage, down: false, mods: mods)
            ])
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 6)
                .frame(minWidth: 52, maxWidth: fillWidth ? .infinity : nil, minHeight: 46)
                .background(BrandPalette.overlayKey, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Numpad & Media Area (Dọc trên iPhone, Ngang khi đủ rộng)

    private var numpadAndMediaArea: some View {
        GeometryReader { geo in
            ScrollView {
                if geo.size.width < 560 {
                    VStack(spacing: 20) {
                        presentationSection
                        Divider().background(Color.white.opacity(0.15))
                        numpadSection
                    }
                    .padding(16)
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        numpadSection
                        Divider().background(Color.white.opacity(0.15)).frame(minHeight: 240)
                        presentationSection
                    }
                    .padding(16)
                }
            }
        }
    }

    private var numpadSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BÀN PHÍM SỐ NUMPAD")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 8) {
                keyButton("7", usage: 0x5F)
                keyButton("8", usage: 0x60)
                keyButton("9", usage: 0x61)
                keyButton("/", usage: 0x54)
            }
            HStack(spacing: 8) {
                keyButton("4", usage: 0x5C)
                keyButton("5", usage: 0x5D)
                keyButton("6", usage: 0x5E)
                keyButton("*", usage: 0x55)
            }
            HStack(spacing: 8) {
                keyButton("1", usage: 0x59)
                keyButton("2", usage: 0x5A)
                keyButton("3", usage: 0x5B)
                keyButton("-", usage: 0x56)
            }
            HStack(spacing: 8) {
                keyButton("0", usage: 0x62)
                keyButton(".", usage: 0x63)
                keyButton("=", usage: 0x58)
                keyButton("+", usage: 0x57)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var presentationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRÌNH CHIẾU SLIDE & MEDIA")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 8) {
                mediaButton("Trình chiếu (F5)", systemName: "play.rectangle.fill", usage: 0x3E)
                mediaButton("Thoát (Esc)", systemName: "xmark.rectangle", usage: 0x29)
            }
            HStack(spacing: 8) {
                mediaButton("Slide trước", systemName: "chevron.left.circle.fill", usage: 0x4B)
                mediaButton("Slide kế", systemName: "chevron.right.circle.fill", usage: 0x4E)
            }
            HStack(spacing: 8) {
                mediaButton("Space", systemName: "space", usage: 0x2C)
                mediaButton("Hoàn tác", systemName: "arrow.uturn.backward", usage: 0x1D, mods: .command)
            }

            Divider().background(Color.white.opacity(0.15)).padding(.vertical, 2)

            Text("ÂM LƯỢNG & PHÁT NHẠC")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 8) {
                systemMediaButton("Bài trước", systemName: "backward.fill", kind: .previous)
                systemMediaButton("Phát / Dừng", systemName: "playpause.fill", kind: .playPause)
                systemMediaButton("Bài kế", systemName: "forward.fill", kind: .next)
            }
            HStack(spacing: 8) {
                systemMediaButton("Tắt tiếng", systemName: "speaker.slash.fill", kind: .mute)
                systemMediaButton("Giảm âm", systemName: "speaker.wave.1.fill", kind: .volumeDown)
                systemMediaButton("Tăng âm", systemName: "speaker.wave.3.fill", kind: .volumeUp)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func systemMediaButton(_ label: String, systemName: String, kind: MediaKeyKind) -> some View {
        Button {
            Haptics.light()
            Task { await model.session.sendMediaKey(kind) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(BrandPalette.overlayKey, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func mediaButton(_ label: String, systemName: String, usage: UInt16, mods: InputModifiers = []) -> some View {
        Button {
            Haptics.light()
            model.session.sendInput([
                .key(usage: usage, down: true, mods: mods),
                .key(usage: usage, down: false, mods: mods)
            ])
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 19))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(BrandPalette.overlayKey, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

/// Bề mặt đa chạm UIKit: 1 ngón di chuyển / chạm đúp giữ kéo; 2 ngón chạm phải / cuộn; 3 ngón Mission Control & Spaces.
private struct TrackpadTouchSurface: UIViewRepresentable {
    let onMove: (Float, Float) -> Void
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onScroll: (Float, Float) -> Void
    let onDragStateChange: (Bool) -> Void
    let onThreeFingerShortcut: (UInt16, InputModifiers) -> Void

    func makeUIView(context: Context) -> TouchPadUIView {
        let view = TouchPadUIView()
        updateCallbacks(view)
        return view
    }

    func updateUIView(_ uiView: TouchPadUIView, context: Context) {
        updateCallbacks(uiView)
    }

    private func updateCallbacks(_ view: TouchPadUIView) {
        view.onMove = onMove
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onScroll = onScroll
        view.onDragStateChange = onDragStateChange
        view.onThreeFingerShortcut = onThreeFingerShortcut
    }
}

@MainActor
private final class TouchPadUIView: UIView {
    var onMove: (Float, Float) -> Void = { _, _ in }
    var onLeftClick: () -> Void = {}
    var onRightClick: () -> Void = {}
    var onScroll: (Float, Float) -> Void = { _, _ in }
    var onDragStateChange: (Bool) -> Void = { _ in }
    var onThreeFingerShortcut: (UInt16, InputModifiers) -> Void = { _, _ in }

    private var tracked: [ObjectIdentifier: CGPoint] = [:]
    private var maxFingers = 0
    private var gestureStartTime: CFTimeInterval = 0
    private var movedBeyondSlop = false
    private var totalDistance: CGFloat = 0
    private var lastSingleTapUpTime: CFTimeInterval = 0
    private var lastSingleTapPoint: CGPoint = .zero
    private var isTapDragArmed = false
    private var isTapDragActive = false
    private var threeFingerDx: CGFloat = 0
    private var threeFingerDy: CGFloat = 0
    private var threeFingerFired = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let now = CACurrentMediaTime()
        if tracked.isEmpty {
            maxFingers = 0
            movedBeyondSlop = false
            totalDistance = 0
            threeFingerDx = 0
            threeFingerDy = 0
            threeFingerFired = false
            gestureStartTime = now
            if touches.count == 1, let first = touches.first {
                let loc = first.location(in: self)
                let delta = hypot(loc.x - lastSingleTapPoint.x, loc.y - lastSingleTapPoint.y)
                isTapDragArmed = (now - lastSingleTapUpTime <= 0.28) && delta <= 24
            } else {
                isTapDragArmed = false
            }
            isTapDragActive = false
        }
        for touch in touches {
            tracked[ObjectIdentifier(touch)] = touch.location(in: self)
        }
        maxFingers = max(maxFingers, tracked.count)
        if maxFingers > 1 { isTapDragArmed = false }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var sumDx: CGFloat = 0
        var sumDy: CGFloat = 0
        var count = 0
        for touch in touches {
            let key = ObjectIdentifier(touch)
            guard let prev = tracked[key] else { continue }
            let loc = touch.location(in: self)
            sumDx += loc.x - prev.x
            sumDy += loc.y - prev.y
            tracked[key] = loc
            count += 1
        }
        guard count > 0 else { return }
        let avgDx = sumDx / CGFloat(count)
        let avgDy = sumDy / CGFloat(count)
        totalDistance += hypot(avgDx, avgDy)
        if totalDistance > 8 { movedBeyondSlop = true }
        guard movedBeyondSlop, avgDx != 0 || avgDy != 0 else { return }

        if maxFingers >= 3 {
            guard !threeFingerFired else { return }
            threeFingerDx += avgDx
            threeFingerDy += avgDy
            if hypot(threeFingerDx, threeFingerDy) >= 42 {
                threeFingerFired = true
                if abs(threeFingerDy) >= abs(threeFingerDx) {
                    onThreeFingerShortcut(threeFingerDy < 0 ? 0x52 : 0x51, .control)
                } else {
                    onThreeFingerShortcut(threeFingerDx < 0 ? 0x4F : 0x50, .control)
                }
            }
            return
        }

        if tracked.count >= 2 || maxFingers >= 2 {
            onScroll(Float(avgDx * 1.5), Float(avgDy * 1.5))
        } else {
            if isTapDragArmed && !isTapDragActive {
                isTapDragActive = true
                onDragStateChange(true)
            }
            let w = max(1, bounds.width)
            let h = max(1, bounds.height)
            onMove(Float(avgDx / w * 1.8), Float(avgDy / h * 1.8))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let endedLoc = touches.first?.location(in: self) ?? .zero
        for touch in touches { tracked.removeValue(forKey: ObjectIdentifier(touch)) }
        guard tracked.isEmpty else { return }
        if isTapDragActive {
            isTapDragActive = false
            isTapDragArmed = false
            onDragStateChange(false)
            return
        }
        isTapDragArmed = false
        guard !movedBeyondSlop else { return }
        let elapsed = CACurrentMediaTime() - gestureStartTime
        if maxFingers >= 2 && elapsed <= 0.35 {
            onRightClick()
        } else if maxFingers == 1 && elapsed <= 0.30 {
            lastSingleTapUpTime = CACurrentMediaTime()
            lastSingleTapPoint = endedLoc
            onLeftClick()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { tracked.removeValue(forKey: ObjectIdentifier(touch)) }
        if tracked.isEmpty && isTapDragActive {
            isTapDragActive = false
            onDragStateChange(false)
        }
        isTapDragArmed = false
    }
}
