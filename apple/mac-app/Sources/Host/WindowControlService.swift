import CoreGraphics
import Foundation
import os
import XdeskWire

/// "Chỉnh cửa sổ" của một phiên: chọn cửa sổ dưới ngón tay (AX), gộp/giới hạn `window.adjust`, áp dụng khung mới
/// và trả `window.selected` theo toạ độ viewer. Chạy trên main actor (AX và `WindowFitter` đều ở đó).
@MainActor
final class WindowControlService {
    static let applyInterval: Duration = .milliseconds(16)
    static let maxTrackedWindows = 64

    private struct Tracked {
        let window: AXWindow
        let appName: String
        var original: CGRect?
    }

    private let log = Logger(subsystem: "vn.xox.xdesk", category: "window-control")
    private let fitter: WindowFitter?
    private let reply: @MainActor (WindowSelected) async -> Void
    private var displayID: CGDirectDisplayID?
    private var viewerSize = CGSize.zero
    private var ids: [UInt: UInt32] = [:]
    private var tracked: [UInt32: Tracked] = [:]
    private var nextId: UInt32 = 1
    private var accumulator = WindowAdjustAccumulator()
    private var limiter = WindowAdjustRateLimiter()
    private var flushTask: Task<Void, Never>?
    private var lastApply: ContinuousClock.Instant?

    init(fitter: WindowFitter?, reply: @escaping @MainActor (WindowSelected) async -> Void) {
        self.fitter = fitter
        self.reply = reply
    }

    /// Màn hình đang chiếu và kích thước khung video theo điểm viewer; gọi lại mỗi khi cấu hình video đổi.
    func configure(displayID: CGDirectDisplayID, viewerSize: CGSize) {
        self.displayID = displayID
        self.viewerSize = viewerSize
    }

    func shutdown() {
        flushTask?.cancel()
        flushTask = nil
        accumulator = WindowAdjustAccumulator()
        tracked.removeAll()
        ids.removeAll()
    }

    // MARK: Chọn

    func pick(x: Double, y: Double) async {
        guard let viewport = currentViewport() else { return await reply(.failure(Self.noWindowMessage)) }
        guard let hit = AXWindowHitTest.window(at: viewport.screenPoint(x: x, y: y)) else {
            return await reply(.failure(Self.noWindowMessage))
        }
        let id = register(hit)
        await reply(selection(id: id, viewport: viewport) ?? .failure(Self.noWindowMessage))
    }

    // MARK: Chỉnh

    func enqueue(_ adjust: WindowAdjust, nowMs: Int64) {
        guard limiter.allow(adjust, nowMs: nowMs) else { return }
        accumulator.add(adjust)
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            await self?.flushLoop()
        }
    }

    private func flushLoop() async {
        while !accumulator.isEmpty, !Task.isCancelled {
            if let last = lastApply {
                let wait = Self.applyInterval - last.duration(to: .now)
                if wait > .zero { try? await Task.sleep(for: wait) }
            }
            guard !Task.isCancelled else { break }
            let batch = accumulator.take()
            lastApply = .now
            var results: [UInt32: WindowSelected] = [:]
            var order: [UInt32] = []
            for adjust in batch {
                results[adjust.windowId] = apply(adjust)
                if !order.contains(adjust.windowId) { order.append(adjust.windowId) }
            }
            for id in order { if let result = results[id] { await reply(result) } }
        }
        flushTask = nil
    }

    private func apply(_ adjust: WindowAdjust) -> WindowSelected {
        guard var entry = tracked[adjust.windowId], let viewport = currentViewport(), let displayID,
              let visible = WindowFitter.targetRect(displayID: displayID) else { return .failure(Self.noWindowMessage) }
        guard let current = entry.window.frame else {
            tracked[adjust.windowId] = nil
            ids[entry.window.key] = nil
            return .failure("Cửa sổ đã đóng hoặc không còn điều khiển được")
        }
        let canResize = entry.window.isResizable
        if entry.original == nil, adjust.op != .preset || adjust.preset != .restore {
            entry.original = current
            tracked[adjust.windowId] = entry
            fitter?.markUserAdjusted(entry.window.key)
        }
        guard let target = targetFrame(adjust, current: current, visible: visible, viewport: viewport, canResize: canResize, original: entry.original) else {
            return .failure(canResize ? "Yêu cầu chỉnh cửa sổ không hợp lệ" : "Cửa sổ này không cho đổi kích thước")
        }
        let moved = target.size == current.size ? entry.window.move(to: target.origin) : entry.window.set(frame: target)
        guard moved else { return .failure("Cửa sổ này không cho chỉnh") }
        return selection(id: adjust.windowId, viewport: viewport) ?? .failure(Self.noWindowMessage)
    }

    private func targetFrame(
        _ adjust: WindowAdjust, current: CGRect, visible: CGRect, viewport: WindowViewport, canResize: Bool, original: CGRect?
    ) -> CGRect? {
        switch adjust.op {
        case .move:
            return WindowAdjustGeometry.moved(current, by: viewport.screenDelta(dx: adjust.dx ?? 0, dy: adjust.dy ?? 0), in: visible)
        case .resize:
            guard canResize, let w = adjust.w, let h = adjust.h else { return nil }
            return WindowAdjustGeometry.resized(current, to: viewport.screenSize(w: w, h: h), in: visible)
        case .preset:
            guard let preset = adjust.preset else { return nil }
            return WindowAdjustGeometry.preset(preset, current: current, visible: visible, original: original, canResize: canResize)
        }
    }

    // MARK: Hỗ trợ

    static let noWindowMessage = "Không có cửa sổ ở đây"

    /// Giới hạn độ dài (wire cho tối đa 256 B UTF-8; 60 ký tự luôn nằm trong giới hạn); rỗng → `nil`.
    private static func shortText(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return String(text.prefix(60))
    }

    private func currentViewport() -> WindowViewport? {
        guard let displayID else { return nil }
        let viewport = WindowViewport(displayBounds: CGDisplayBounds(displayID), viewerSize: viewerSize)
        return viewport.isValid ? viewport : nil
    }

    private func register(_ hit: AXWindowHitTest.Hit) -> UInt32 {
        if let existing = ids[hit.window.key] {
            tracked[existing] = Tracked(window: hit.window, appName: hit.appName, original: tracked[existing]?.original)
            return existing
        }
        if tracked.count >= Self.maxTrackedWindows { tracked.removeAll(); ids.removeAll() }
        let id = nextId
        nextId = nextId == UInt32.max ? 1 : nextId + 1
        ids[hit.window.key] = id
        tracked[id] = Tracked(window: hit.window, appName: hit.appName, original: nil)
        return id
    }

    private func selection(id: UInt32, viewport: WindowViewport) -> WindowSelected? {
        guard let entry = tracked[id], let frame = entry.window.frame else { return nil }
        return WindowSelected(
            ok: true, windowId: id, app: Self.shortText(entry.appName), title: Self.shortText(entry.window.title),
            frame: viewport.viewerFrame(fromScreen: frame), resizable: entry.window.isResizable)
    }
}
