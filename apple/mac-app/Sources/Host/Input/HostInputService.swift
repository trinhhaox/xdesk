import CoreGraphics
import Foundation
import os
import XdeskInput
import XdeskWire

/// Nhận input của một phiên (gói UDP `input` + control `input.text`) và tiêm vào màn hình đang capture:
/// giới hạn tốc độ → sắp xếp theo seq (`InputReceiver`) → `CoordinateMapper` → `EventInjecting`, kèm watchdog chống kẹt.
actor HostInputService {
    static let watchdogIntervalMs = 250

    private let streamId: UInt16
    private let mapper: CoordinateMapper
    private let injector: any EventInjecting
    private let guardian: StuckInputGuard
    private let isTrusted: @Sendable () -> Bool
    private let onSecureInput: @Sendable (Bool) -> Void
    private let log = Logger(subsystem: "vn.xox.xdesk", category: "host-input")
    private var receiver = InputReceiver()
    private var limiter = InputRateLimiter()
    private var watchdog: Task<Void, Never>?
    private var warnedUntrusted = false
    private(set) var malformedPacketCount = 0

    init(
        streamId: UInt16, mapper: CoordinateMapper, injector: any EventInjecting = CGEventInjector(),
        isTrusted: @escaping @Sendable () -> Bool = { AccessibilityPermission.isGranted },
        onSecureInput: @escaping @Sendable (Bool) -> Void = { _ in }
    ) {
        self.streamId = streamId
        self.mapper = mapper
        self.injector = injector
        self.guardian = StuckInputGuard(injector: injector)
        self.isTrusted = isTrusted
        self.onSecureInput = onSecureInput
    }

    func start() {
        guard watchdog == nil else { return }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(Self.watchdogIntervalMs))
                await self?.tickWatchdog()
            }
        }
    }

    /// Nhả mọi nút/phím đang giữ rồi dừng watchdog (phiên kết thúc / viewer ngắt).
    func shutdown() {
        watchdog?.cancel()
        watchdog = nil
        guardian.releaseAll()
    }

    /// Xử lý một gói media; trả input-ack khi gói có sự kiện cần tin cậy.
    func handle(_ packet: MediaPacket, nowMs: Int64 = HostInputService.uptimeMs) -> MediaPacket? {
        guard packet.header.type == .input, packet.header.streamId == streamId else { return nil }
        let events: [InputEvent]
        do { events = try InputEvent.decodeBatch(packet.payload) } catch {
            malformedPacketCount += 1
            log.error("gói input hỏng: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guardian.noteActivity(nowMs: nowMs)
        let allowed = limiter.take(events.count, nowMs: nowMs)
        if allowed < events.count { log.notice("vượt 1000 sự kiện/s, bỏ \(events.count - allowed)") }
        let ordered = receiver.accept(Array(events.prefix(allowed)), nowMs: nowMs)
        if isTrusted() {
            ordered.forEach(apply)
        } else if !ordered.isEmpty, !warnedUntrusted {
            warnedUntrusted = true
            log.error("chưa có quyền Trợ năng, bỏ input")
        }
        guard events.contains(where: \.isReliable) else { return nil }
        return .inputAck(streamId: streamId, ack: InputAck(seq: receiver.ackSeq))
    }

    func typeText(_ text: String) {
        guard isTrusted() else { return }
        let outcome = TextInjector().type(text)
        onSecureInput(outcome == .typedWhileSecureInput)
    }

    // MARK: Tiêm

    private func tickWatchdog() {
        if guardian.tick(nowMs: Self.uptimeMs) { log.notice("không nhận input khi đang giữ nút/phím: đã nhả") }
    }

    private func apply(_ event: InputEvent) {
        let flags = InputModifiers(rawValue: event.mods).cgEventFlags
        switch event.kind {
        case .move:
            let point = mapper.point(x: event.x, y: event.y)
            guardian.moved(to: point)
            injector.mouseMove(to: point, held: guardian.primaryButton, flags: flags)
        case .down:
            let point = mapper.point(x: event.x, y: event.y), button = MouseButton(wire: event.button)
            guardian.buttonDown(button, at: point)
            injector.mouseButton(button, down: true, at: point, clickCount: Int(event.dx), flags: flags)
        case .up:
            let point = mapper.point(x: event.x, y: event.y), button = MouseButton(wire: event.button)
            guard guardian.buttonUp(button, at: point) else { return }
            injector.mouseButton(button, down: false, at: point, clickCount: Int(event.dx), flags: flags)
        case .scroll:
            guard event.dx != 0 || event.dy != 0 else { return }
            injector.scroll(dx: Self.clampedPixels(event.dx), dy: Self.clampedPixels(event.dy), flags: flags)
        case .key:
            applyKey(event, flags: flags)
        case .textRef, .touch:
            break
        }
    }

    private func applyKey(_ event: InputEvent, flags: CGEventFlags) {
        guard let code = HidKeyMap.macKeyCode(forHidUsage: event.keyUsage) else { return }
        if event.button != 0 {
            guardian.keyDown(code)
        } else if !guardian.keyUp(code) {
            return
        }
        injector.key(code, down: event.button != 0, flags: flags)
    }

    private static func clampedPixels(_ value: Float) -> Int32 {
        Int32(max(-10_000, min(10_000, value.rounded())))
    }

    nonisolated static var uptimeMs: Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }
}
