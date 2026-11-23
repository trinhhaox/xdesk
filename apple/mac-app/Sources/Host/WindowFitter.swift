import AppKit
import os

/// Bản sao "Vừa với điện thoại"/"Tối ưu thao tác": desktop Mac đổi sang cỡ điện thoại nhưng cửa sổ app giữ khung cũ (chỉ phủ
/// một phần). Fitter co/dời cửa sổ app thường cho vừa `visibleFrame` của màn hình đó, nhớ khung gốc và trả lại khi hết phiên fit.
/// Dùng chung cho mọi `HostSession`: xoay máy/đổi kiểu mở lại phiên nhưng cửa sổ giữ khung gốc ban đầu (khôi phục trễ ~1 s
/// để phiên kế tiếp kịp `begin` và huỷ việc khôi phục).
@MainActor
final class WindowFitter {
    static let enabledKey = "xdesk.host.fitWindows"
    private static let settleDelay: Duration = .milliseconds(400)
    private static let restoreDelay: Duration = .milliseconds(800)
    private static let pollInterval: Duration = .milliseconds(1500)

    /// Mặc định bật.
    static var isEnabledByUser: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    private let log = Logger(subsystem: "vn.xox.xdesk", category: "window-fit")
    private let isEnabled: () -> Bool
    private var ledger = WindowFrameLedger<UInt>()
    private var elements: [UInt: AXWindow] = [:]
    /// Cửa sổ người dùng đã tự chỉnh từ điện thoại ("Chỉnh cửa sổ"): không co lại và không khôi phục về khung gốc.
    private var userAdjusted: Set<UInt> = []
    private var users = 0
    private var displayID: CGDirectDisplayID?
    private var pollTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?

    init(isEnabled: @escaping () -> Bool = { WindowFitter.isEnabledByUser }) {
        self.isEnabled = isEnabled
        // Thoát app giữa phiên: trả cửa sổ về khung gốc (phiên bị cắt đột ngột nên không có `end()`).
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreNow() }
        }
    }

    /// Người dùng tự chỉnh cửa sổ `key` (`AXWindow.key`): bỏ khỏi danh sách khôi phục và không bao giờ co lại nữa.
    func markUserAdjusted(_ key: UInt) {
        userAdjusted.insert(key)
        ledger.forget(key)
        elements[key] = nil
    }

    /// Gọi TRƯỚC khi đổi màn hình Mac: macOS tự kẹp cửa sổ vào desktop mới nên khung gốc phải ghi nhận trước đó.
    func prepare() {
        guard isEnabled(), AccessibilityPermission.isGranted else { return }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            for window in AXWindow.windows(ofPid: app.processIdentifier) where window.isFittable && !userAdjusted.contains(window.key) {
                guard let frame = window.frame else { continue }
                ledger.remember(window.key, frame: frame)
                elements[window.key] = window
            }
        }
    }

    /// Một viewer vào chế độ fit (hoặc cấu hình lại): co lại mọi cửa sổ theo màn hình hiện tại rồi theo dõi cửa sổ mới.
    func begin(displayID: CGDirectDisplayID) async {
        guard isEnabled(), AccessibilityPermission.isGranted else { return }
        users += 1
        self.displayID = displayID
        restoreTask?.cancel()
        restoreTask = nil
        try? await Task.sleep(for: Self.settleDelay)
        guard users > 0 else { return }
        log.notice("co \(self.fitWindows(onlyNew: false)) cửa sổ cho vừa màn hình")
        startPolling()
    }

    /// Viewer rời chế độ fit: khi không còn ai thì khôi phục (trễ để phiên mới, nếu có, huỷ được).
    func end() {
        guard users > 0 else { return }
        users -= 1
        guard users == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
        let fitted = displayID
        restoreTask = Task { [weak self] in
            await Self.waitUntilGone(fitted)
            guard !Task.isCancelled else { return }
            self?.restoreNow()
        }
    }

    /// Dừng host: chờ màn hình Mac trở lại như cũ rồi khôi phục (không để cửa sổ kẹt ở khung điện thoại).
    func restoreAfterSettle() async {
        guard ledger.count > 0 else { return }
        await Self.waitUntilGone(displayID)
        restoreNow()
    }

    /// Khôi phục ngay (dừng host, thoát app). Cửa sổ đã đóng thì bỏ qua.
    func restoreNow() {
        restoreTask?.cancel()
        restoreTask = nil
        pollTask?.cancel()
        pollTask = nil
        users = 0
        var restored = 0
        for entry in ledger.drain() where elements[entry.key]?.set(frame: entry.frame) == true { restored += 1 }
        elements.removeAll()
        userAdjusted.removeAll()
        if restored > 0 { log.notice("khôi phục \(restored) cửa sổ về khung gốc") }
    }

    /// Màn hình ảo biến mất (≤ ~5 s) rồi chờ thêm một nhịp cho desktop Mac trở lại cỡ cũ; khôi phục sớm hơn thì macOS kẹp khung vào desktop nhỏ.
    private static func waitUntilGone(_ displayID: CGDirectDisplayID?) async {
        if let displayID {
            for _ in 0..<50 where CGDisplayIsOnline(displayID) != 0 { try? await Task.sleep(for: .milliseconds(100)) }
        }
        try? await Task.sleep(for: restoreDelay)
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                self?.fitWindows(onlyNew: true)
            }
        }
    }

    /// Trả về số cửa sổ đã co. `onlyNew`: chỉ cửa sổ chưa từng co (người dùng tự đổi khung thì không bị co lại liên tục).
    @discardableResult
    private func fitWindows(onlyNew: Bool) -> Int {
        guard let displayID, let target = Self.targetRect(displayID: displayID) else { return 0 }
        let others = Self.otherScreenRects(except: displayID)
        var fitted = 0
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != getpid() {
            for window in AXWindow.windows(ofPid: app.processIdentifier) where window.isFittable && !userAdjusted.contains(window.key) {
                guard let frame = window.frame, !others.contains(where: { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }) else { continue }
                if onlyNew, ledger.contains(window.key), !WindowFitGeometry.needsRefit(frame, in: target) { continue }
                ledger.remember(window.key, frame: frame)
                elements[window.key] = window
                if fit(window, into: target) { fitted += 1 }
            }
        }
        return fitted
    }

    /// Đặt cỡ = vùng hiển thị; nếu cửa sổ không co nổi (kích thước tối thiểu) thì đo cỡ thật rồi căn giữa.
    private func fit(_ window: AXWindow, into target: CGRect) -> Bool {
        guard window.set(frame: target) else { return false }
        if let actual = window.currentSize, actual.width > target.width + 0.5 || actual.height > target.height + 0.5 {
            window.move(to: WindowFitGeometry.frame(minSize: actual, in: target).origin)
        }
        return true
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID } ?? NSScreen.main
    }

    /// Vùng hiển thị (trừ menu bar/Dock) của màn hình `displayID`, toạ độ AX.
    static func targetRect(displayID: CGDirectDisplayID) -> CGRect? {
        guard let screen = screen(for: displayID), let primary = NSScreen.screens.first else { return nil }
        return WindowFitGeometry.axRect(fromVisibleFrame: screen.visibleFrame, primaryHeight: primary.frame.height)
    }

    /// Màn hình khác (không phải màn hình đang fit): cửa sổ nằm trên đó (vd. màn hình của agent) bị bỏ qua.
    private static func otherScreenRects(except displayID: CGDirectDisplayID) -> [CGRect] {
        guard let primary = NSScreen.screens.first, let current = screen(for: displayID) else { return [] }
        return NSScreen.screens.filter { $0 != current }.map { WindowFitGeometry.axRect(fromVisibleFrame: $0.frame, primaryHeight: primary.frame.height) }
    }
}
