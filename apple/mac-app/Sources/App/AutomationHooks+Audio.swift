#if DEBUG
import Foundation
import Network
import os
import XdeskTransport
import XdeskViewer

/// Cờ kiểm thử cho audio và USB (Debug):
///   --auto-approve-audio        khi tự duyệt ghép đôi, cấp luôn quyền âm thanh (mặc định tắt)
///   --audio-narrow              host coi đường truyền là hẹp (Tailscale/USB) → dùng AAC-ELD thay vì PCM
///   --audio-mute-local          bật "Chỉ phát trên thiết bị" (không lưu cài đặt)
///   --audio-report              mỗi 5 ms hỏi số liệu audio của viewer; in `xdesk-audio ...` mỗi giây và `xdesk-audio-onset wallMs=` khi có tiếng
///   --usb-loopback              giả lập cáp USB: viewer nghe cổng loopback, host nối vào như thể qua usbmuxd (cần đã ghép đôi: --pair-token self trước)
///   --usb-probe                 in thiết bị usbmuxd đang báo sau 3 giây
enum AudioAutomation {
    private static let log = Logger(subsystem: "vn.xox.xdesk", category: "automation-audio")

    @MainActor
    static func configure(host: HostController, args: [String]) {
        if args.contains("--audio-mute-local") { host.audioOptions.setMuteLocalOutput(true, persist: false) }
    }

    @MainActor
    static func run(host: HostController, viewer: ViewerController, args: [String]) async {
        if args.contains("--usb-probe") { await usbProbe(host: host) }
        if args.contains("--usb-loopback") { await usbLoopback(host: host, viewer: viewer) }
        if args.contains("--audio-report") { await report(viewer: viewer) }
    }

    @MainActor
    private static func usbProbe(host: HostController) async {
        try? await Task.sleep(for: .seconds(3))
        let devices = host.usb.devices.map { "\($0.deviceID):\($0.shortSerial)" }.joined(separator: ",")
        print("xdesk-usb-probe status=\(host.usb.status) devices=[\(devices)]")
        fflush(stdout)
    }

    @MainActor
    private static func usbLoopback(host: HostController, viewer: ViewerController) async {
        // Cần đã ghép đôi: chờ phiên ghép (--pair-token self) bắt đầu rồi kết thúc (--disconnect-after) trước khi giả lập cáp.
        for _ in 0..<80 where viewer.session == nil { try? await Task.sleep(for: .milliseconds(250)) }
        for _ in 0..<160 where viewer.session != nil { try? await Task.sleep(for: .milliseconds(250)) }
        try? await Task.sleep(for: .seconds(1))
        let queue = DispatchQueue(label: "xdesk.usb.loopback")
        do {
            let listener = try NWListener(using: .tcp, on: .any)
            listener.newConnectionHandler = { connection in
                Task { @MainActor in
                    do {
                        let tunnel = try await ControlConnection.acceptUsbTunnel(connection)
                        await viewer.connectTunnel(tunnel, title: "usb-loopback")
                        print("xdesk-usb-loopback viewer state=\(String(describing: viewer.session?.state)) error=\(viewer.errorMessage ?? "-")")
                        fflush(stdout)
                        await wiggleCursor(viewer)
                    } catch { log.error("usb-loopback viewer: \(error.localizedDescription, privacy: .public)") }
                }
            }
            let port = try await readyPort(of: listener, queue: queue)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            let tunnel = NWConnection(host: "127.0.0.1", port: nwPort, using: .tcp)
            try await waitReady(tunnel, queue: queue)
            try await host.adoptUsb(tunnel)
            print("xdesk-usb-loopback host adopted tunnel on port \(port)")
            fflush(stdout)
        } catch {
            print("xdesk-usb-loopback error: \(error.localizedDescription)")
            fflush(stdout)
        }
    }

    /// Di chuyển con trỏ trên màn hình ảo để SCK có khung mới (màn tĩnh không phát khung); input cũng đi qua đường hầm.
    @MainActor
    private static func wiggleCursor(_ viewer: ViewerController) async {
        for step in 0..<60 {
            guard let session = viewer.session else { return }
            session.sendInput([.move(x: 0.2 + Float(step % 30) * 0.02, y: 0.5)])
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func readyPort(of listener: NWListener, queue: DispatchQueue) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, any Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { state in
                let take = resumed.withLock { done -> Bool in
                    guard !done else { return false }
                    switch state {
                    case .ready, .failed, .cancelled: done = true; return true
                    default: return false
                    }
                }
                guard take else { return }
                if case .ready = state, let port = listener.port?.rawValue { cont.resume(returning: port) } else {
                    cont.resume(throwing: TransportError.listenerFailed("usb-loopback"))
                }
            }
            listener.start(queue: queue)
        }
    }

    private static func waitReady(_ connection: NWConnection, queue: DispatchQueue) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            connection.stateUpdateHandler = { state in
                let take = resumed.withLock { done -> Bool in
                    guard !done else { return false }
                    switch state {
                    case .ready, .failed, .cancelled: done = true; return true
                    default: return false
                    }
                }
                guard take else { return }
                if case .ready = state { cont.resume() } else { cont.resume(throwing: TransportError.connectionFailed("usb-loopback")) }
            }
            connection.start(queue: queue)
        }
    }

    @MainActor
    private static func report(viewer: ViewerController) async {
        var lastOnsets = 0
        var lastPrint = ContinuousClock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(5))
            guard let session = viewer.session, let stats = session.audioStats else { continue }
            if stats.onsets != lastOnsets {
                lastOnsets = stats.onsets
                print("xdesk-audio-onset wallMs=\(stats.lastOnsetUnixMs) peak=\(stats.lastPeak)")
                fflush(stdout)
            }
            guard ContinuousClock.now - lastPrint >= .seconds(1) else { continue }
            lastPrint = .now
            let latency = session.audioLatencyEstimateMs.map(String.init) ?? "-"
            let codec = stats.codec.map { "\($0)" } ?? "-"
            print("xdesk-audio packets=\(stats.packets) codec=\(codec) depthMs=\(stats.jitterDepthMs) underruns=\(stats.underruns) concealed=\(stats.concealedFrames) holdMs=\(stats.hostHoldMs) outLatMs=\(stats.outputLatencyMs) rttMs=\(session.rttMs ?? -1) estLatencyMs=\(latency) peak=\(stats.lastPeak) malformed=\(stats.malformed) fps=\(session.fps) kbps=\(session.recvKbps)")
            fflush(stdout)
        }
    }
}
#endif
