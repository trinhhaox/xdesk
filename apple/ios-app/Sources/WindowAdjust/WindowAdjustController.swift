import Foundation
import Observation
import XdeskInput
import XdeskViewer
import XdeskWire

/// Trạng thái chế độ "Chỉnh cửa sổ": cửa sổ đang chọn, frame dự đoán phía viewer (theo ngón tay ngay) và hàng đợi lệnh gửi host.
/// Lệnh đi qua một `AsyncStream` nên giữ đúng thứ tự; cử chỉ chỉ cập nhật frame dự đoán, mỗi khung hình `flush()` mới gửi phần chênh.
@MainActor
@Observable
final class WindowAdjustController {
    /// Host nhận tối đa 60 lệnh/giây; đổi cỡ gửi kèm `move` nên giãn tối thiểu 1/30 giây giữa hai lần đổi cỡ.
    private static let minResizeInterval: TimeInterval = 1.0 / 30
    /// Sau lần gửi cuối chừng này thì mới nhận frame host trả (tránh khung nhảy lùi theo trả lời cũ).
    private static let settleDelay: Duration = .milliseconds(200)

    private(set) var isActive = false
    private(set) var windowId: UInt32?
    private(set) var appName: String?
    private(set) var frame: WindowFrame?
    private(set) var resizable = true

    @ObservationIgnored var onNotice: ((String) -> Void)?
    /// Frame/lựa chọn đổi: lớp vẽ UIKit cập nhật khung viền.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let session: ViewerSession
    @ObservationIgnored private var continuation: AsyncStream<WindowAdjust>.Continuation?
    @ObservationIgnored private var sender: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var deferredFrame: WindowFrame?
    @ObservationIgnored private var sent: WindowFrame?
    @ObservationIgnored private var gesturing = false
    @ObservationIgnored private var lastSendAt = Date.distantPast
    @ObservationIgnored private var lastResizeAt = Date.distantPast

    var hasSelection: Bool { windowId != nil && frame != nil }

    init(session: ViewerSession) { self.session = session }

    func enter() {
        guard !isActive else { return }
        isActive = true
        let (stream, continuation) = AsyncStream.makeStream(of: WindowAdjust.self)
        self.continuation = continuation
        sender = Task { [session] in
            for await adjust in stream { await session.adjustWindow(adjust) }
        }
        session.onWindowSelected = { [weak self] in self?.received($0) }
    }

    func exit() {
        guard isActive else { return }
        isActive = false
        continuation?.finish()
        continuation = nil
        sender = nil
        settleTask?.cancel()
        session.onWindowSelected = nil
        windowId = nil; appName = nil; frame = nil; sent = nil; deferredFrame = nil
        gesturing = false
        onChange?()
    }

    func pick(x: Double, y: Double) {
        Task { await session.pickWindow(x: x, y: y) }
    }

    func preset(_ preset: WindowPreset) {
        guard let windowId else { return }
        continuation?.yield(.preset(windowId: windowId, preset))
    }

    // MARK: Cử chỉ

    func beginGesture() { gesturing = true; settleTask?.cancel() }

    func endGesture() {
        flush(force: true)
        gesturing = false
        scheduleSettle()
    }

    /// Frame dự đoán mới từ cử chỉ (đã kẹp tối thiểu).
    func predict(_ next: WindowFrame) {
        frame = next
        onChange?()
    }

    /// Gửi phần chênh giữa frame dự đoán và frame host (theo lệnh đã gửi). Gọi mỗi khung hình khi đang kéo.
    func flush(force: Bool = false) {
        guard let windowId, let frame, let sent else { return }
        let now = Date()
        let plan = WindowGestureMath.plan(windowId: windowId, from: sent, to: frame)
        guard !plan.ops.isEmpty else { return }
        let resizes = plan.ops.contains { $0.op == .resize }
        if resizes, !force, now.timeIntervalSince(lastResizeAt) < Self.minResizeInterval { return }
        if resizes { lastResizeAt = now }
        lastSendAt = now
        self.sent = plan.applied
        plan.ops.forEach { continuation?.yield($0) }
    }

    // MARK: Trả lời từ host

    private func received(_ selected: WindowSelected) {
        guard isActive else { return }
        guard selected.ok, let id = selected.windowId, let hostFrame = selected.frame else {
            onNotice?(selected.message ?? "Không chỉnh được cửa sổ này")
            return
        }
        if id != windowId { Haptics.light() }
        windowId = id
        appName = selected.app
        resizable = selected.resizable ?? true
        if gesturing || Date().timeIntervalSince(lastSendAt) < 0.2 {
            deferredFrame = hostFrame
            scheduleSettle()
        } else {
            adopt(hostFrame)
        }
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self, !self.gesturing, let latest = self.deferredFrame else { return }
            self.adopt(latest)
        }
    }

    private func adopt(_ hostFrame: WindowFrame) {
        deferredFrame = nil
        frame = hostFrame
        sent = hostFrame
        onChange?()
    }
}
