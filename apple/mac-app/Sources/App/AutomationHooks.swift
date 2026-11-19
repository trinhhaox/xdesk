#if DEBUG
import AppKit
import Foundation
import os
import XdeskCrypto
import XdeskInput
import XdeskViewer

/// Chỉ build Debug: điều khiển app bằng tham số dòng lệnh để kiểm thử không cần bấm UI.
///   --auto-host                 bật host ngay
///   --auto-connect host:port    viewer tự kết nối (kèm --retina / --latency-overlay / --fullscreen)
///   --auto-connect bonjour      viewer kết nối tới host đầu tiên tìm thấy qua Bonjour
///   --input-probe x,y           sau khi kết nối: gửi move tới (x,y) chuẩn hoá rồi log quyền Trợ năng + vị trí con trỏ thật
///   --input-click x,y           sau khi kết nối: click trái tại (x,y) chuẩn hoá rồi cuộn +60/-60; log vị trí con trỏ và delta cuộn thấy được ở app khác
///   --plaintext                 tắt mã hoá (chỉ Debug; mặc định Debug cũng mã hoá và dùng ghép đôi thật)
///   --open-pairing-window       mở cửa sổ "Ghép đôi thiết bị mới" sau khi host bật (kèm --snapshot-pairing-window <png> để ghi ảnh nội dung; thêm --snapshot-when-streaming để chụp sau khi có viewer)
///   --snapshot-approval <png>   ghi ảnh hộp thoại cho phép ghép đôi khi nó hiện
///   --open-devices-window       mở cửa sổ "Thiết bị đã ghép"
///   --auto-approve-pairing      host tự "Cho phép"/"Khớp" mọi yêu cầu ghép đôi (chỉ để kiểm thử)
///   --print-pair-uri [file]     host giữ QR mở: in `xdesk-pair-uri <uri>` ra stdout (và ghi vào file nếu có), tự đổi khi hết hạn
///   --pair-token <uri|self|@file>  viewer ghép đôi bằng QR (self = QR của host trong cùng tiến trình)
///   --pair-sas host:port        viewer ghép đôi bằng so mã 6 số (in `xdesk-sas-viewer-code NNN NNN`; host in `xdesk-sas-host-code`)
///   --revoke-viewers-after <giây>  host thu hồi mọi viewer đã ghép → phiên phải bị cắt ≤ 1 s
///   --disconnect-after <giây>   viewer tự ngắt (host vẫn chạy) → màn hình ảo phải biến mất
///   --enable-mcp [tệp]          bật máy chủ MCP (không lưu cài đặt); có tệp thì ghi token vào đó (0600) cho script curl
///   --auto-approve-agent        bỏ qua hộp thoại duyệt quyền/ứng dụng của agent (chỉ Debug, để kiểm thử tự động; không tồn tại ở Release)
///   SIGUSR1 / SIGUSR2           tạm dừng / tiếp tục agent như phím tắt ⌃⌥⌘. (chỉ Debug, đo độ trễ "control paused")
///   --quit-after <giây>         tự thoát
@MainActor
enum AutomationHooks {
    private static let log = Logger(subsystem: "vn.xox.xdesk", category: "automation")

    static func run(host: HostController, viewer: ViewerController, security: SecurityCenter, pairing: PairingCoordinator, agent: AgentController) async {
        let args = CommandLine.arguments
        viewer.options.retina = args.contains("--retina")
        viewer.options.fullScreen = args.contains("--fullscreen")
        viewer.options.latencyOverlay = args.contains("--latency-overlay")
        if args.contains("--auto-host") {
            await host.start()
            log.notice("auto-host status: \(String(describing: host.status), privacy: .public)")
        }
        if args.contains("--auto-approve-agent") { agent.enableAutoApprove() }
        installAgentSignals(agent)
        if args.contains("--enable-mcp") {
            await agent.setEnabled(true, persist: false)
            log.notice("auto-mcp status: \(String(describing: agent.status), privacy: .public)")
            if let path = value(after: "--enable-mcp", in: args), !path.hasPrefix("--") { agent.writeTokenForAutomation(to: path) }
        }
        if let path = value(after: "--snapshot-approval", in: args) {
            Task { await snapshotApproval(pairing, to: path) }
        }
        if args.contains("--open-devices-window") { pairing.showDevicesWindow() }
        if args.contains("--open-pairing-window") {
            await pairing.showQrWindow()
            let path = value(after: "--snapshot-pairing-window", in: args)
            let waitForStream = args.contains("--snapshot-when-streaming")
            Task { await snapshotPairingWindow(pairing, host: host, to: path, waitForStream: waitForStream) }
        }
        if args.contains("--print-pair-uri") { Task { await keepPairUriOpen(host: host, security: security, file: value(after: "--print-pair-uri", in: args)) } }
        if let seconds = value(after: "--revoke-viewers-after", in: args).flatMap(Double.init) {
            Task { await revokeViewers(after: seconds, security: security) }
        }
        if let token = value(after: "--pair-token", in: args) {
            await pairWithToken(token, viewer: viewer, security: security)
        } else if let sas = value(after: "--pair-sas", in: args) {
            await pairWithSas(sas, viewer: viewer)
        } else if let value = value(after: "--auto-connect", in: args) {
            await autoConnect(value, viewer: viewer)
        }
        if let probe = value(after: "--input-probe", in: args) {
            await inputProbe(probe, viewer: viewer)
        }
        if let click = value(after: "--input-click", in: args) {
            await inputClick(click, viewer: viewer)
        }
        if let seconds = value(after: "--disconnect-after", in: args).flatMap(Double.init) {
            try? await Task.sleep(for: .seconds(seconds))
            await viewer.disconnect()
            log.notice("viewer disconnected by automation")
        }
        if let seconds = value(after: "--quit-after", in: args).flatMap(Double.init) {
            try? await Task.sleep(for: .seconds(seconds))
            await viewer.disconnect()
            await host.stop()
            NSApplication.shared.terminate(nil)
        }
    }

    private static var signalSources: [DispatchSourceSignal] = []

    private static func installAgentSignals(_ agent: AgentController) {
        for (number, action) in [(SIGUSR1, true), (SIGUSR2, false)] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { agent.debugSetPaused(action) }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Chờ hộp thoại "muốn ghép đôi" xuất hiện rồi ghi PNG nội dung.
    private static func snapshotApproval(_ pairing: PairingCoordinator, to path: String) async {
        for _ in 0..<240 where pairing.approvalWindowForTesting == nil { try? await Task.sleep(for: .milliseconds(250)) }
        try? await Task.sleep(for: .seconds(1))
        log.notice("approval snapshot written=\(pairing.approvalWindowForTesting?.writeSnapshot(to: path) ?? false, privacy: .public)")
    }

    /// In trạng thái cửa sổ ghép đôi và (nếu có đường dẫn) vẽ nội dung ra PNG trong tiến trình.
    private static func snapshotPairingWindow(_ pairing: PairingCoordinator, host: HostController, to path: String?, waitForStream: Bool) async {
        if waitForStream { for _ in 0..<60 where host.activeViewerCount == 0 { try? await Task.sleep(for: .milliseconds(250)) } }
        for _ in 0..<20 where pairing.security.qrURI == nil && pairing.availability.blockedMessage == nil { try? await Task.sleep(for: .milliseconds(250)) }
        try? await Task.sleep(for: .seconds(1.5))
        let state = pairing.availability.blockedMessage ?? "qr=\(pairing.security.qrURI != nil)"
        log.notice("pairing-window: \(state, privacy: .public) frame=\(pairing.qrWindowForTesting?.windowFrameDescription ?? "-", privacy: .public)")
        guard let path, !path.hasPrefix("--"), let window = pairing.qrWindowForTesting else { return }
        log.notice("pairing-window snapshot written=\(window.writeSnapshot(to: path), privacy: .public)")
    }

    private static func autoConnect(_ value: String, viewer: ViewerController) async {
        try? await Task.sleep(for: .seconds(1))
        let target: ViewerTarget?
        if value == "bonjour" {
            viewer.startBrowsing()
            for _ in 0..<20 where viewer.hosts.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
            log.notice("bonjour hosts: \(viewer.hosts.map(\.name).joined(separator: ","), privacy: .public)")
            target = viewer.hosts.first.map { ViewerTarget.discovered($0) }
        } else {
            target = ViewerTarget.parse(manual: value)
        }
        guard let target else { log.error("auto-connect: no target for \(value, privacy: .public)"); return }
        await viewer.connect(to: target, title: value)
        log.notice("auto-connect state: \(String(describing: viewer.session?.state), privacy: .public) error: \(viewer.errorMessage ?? "-", privacy: .public)")
    }

    /// Giữ một QR mở trong suốt phiên kiểm thử và in URI mỗi khi đổi (stdout, không qua os_log).
    private static func keepPairUriOpen(host: HostController, security: SecurityCenter, file: String?) async {
        var printed: String?
        while !Task.isCancelled {
            if case .listening(let port) = host.status, security.qrURI == nil { await security.startQrPairing(port: port) }
            if let uri = security.qrURI?.string, uri != printed {
                printed = uri
                print("xdesk-pair-uri \(uri)")
                fflush(stdout)
                if let file, !file.hasPrefix("--") { try? Data(uri.utf8).write(to: URL(fileURLWithPath: file), options: .atomic) }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private static func pairWithToken(_ token: String, viewer: ViewerController, security: SecurityCenter) async {
        try? await Task.sleep(for: .seconds(1.5))
        var text = token
        if token == "self" {
            for _ in 0..<40 where security.qrURI == nil { try? await Task.sleep(for: .milliseconds(250)) }
            text = security.qrURI?.string ?? ""
        } else if token.hasPrefix("@") {
            text = (try? String(contentsOfFile: String(token.dropFirst()), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        guard let uri = try? PairingURI.parse(text) else { log.error("pair-token: URI không hợp lệ"); return }
        await viewer.pair(with: uri, title: "pair")
        log.notice("pair-token state: \(String(describing: viewer.session?.state), privacy: .public) error: \(viewer.errorMessage ?? "-", privacy: .public)")
    }

    private static func pairWithSas(_ hostPort: String, viewer: ViewerController) async {
        try? await Task.sleep(for: .seconds(1.5))
        guard let target = ViewerTarget.parse(manual: hostPort) else { log.error("pair-sas: sai định dạng"); return }
        await viewer.connect(to: target, title: "sas", auth: .sas(onCode: { code in
            print("xdesk-sas-viewer-code \(code)")
            fflush(stdout)
        }))
        log.notice("pair-sas state: \(String(describing: viewer.session?.state), privacy: .public) error: \(viewer.errorMessage ?? "-", privacy: .public)")
    }

    private static func revokeViewers(after seconds: Double, security: SecurityCenter) async {
        try? await Task.sleep(for: .seconds(seconds))
        await security.refresh()
        for device in security.pairedViewers { await security.revoke(deviceId: device.id) }
        log.notice("revoked \(security.pairedViewers.count, privacy: .public) remaining viewers")
    }

    private static func inputProbe(_ value: String, viewer: ViewerController) async {
        let parts = value.split(separator: ",").compactMap { Float($0) }
        guard parts.count == 2, let session = viewer.session else { log.error("input-probe: cần x,y và viewer đã kết nối"); return }
        try? await Task.sleep(for: .seconds(2))
        log.notice("input-probe: accessibility=\(AccessibilityPermission.isGranted, privacy: .public)")
        let before = CGEvent(source: nil)?.location ?? .zero
        log.notice("input-probe: cursor before=\(NSStringFromPoint(before), privacy: .public)")
        for (x, y) in [(parts[0], parts[1]), (parts[0] / 2, parts[1] / 2)] {
            session.sendInput([.move(x: x, y: y)])
            try? await Task.sleep(for: .milliseconds(500))
            let cursor = CGEvent(source: nil)?.location ?? .zero
            log.notice("input-probe: sent (\(x), \(y)) cursor=\(NSStringFromPoint(cursor), privacy: .public)")
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &count)
        let layout = ids.prefix(Int(count)).map { "\($0)=\(NSStringFromRect(CGDisplayBounds($0)))" }.joined(separator: " ")
        log.notice("input-probe: displays: \(layout, privacy: .public)")
    }

    private static func inputClick(_ value: String, viewer: ViewerController) async {
        let parts = value.split(separator: ",").compactMap { Float($0) }
        guard parts.count == 2, let session = viewer.session else { log.error("input-click: cần x,y và viewer đã kết nối"); return }
        try? await Task.sleep(for: .seconds(2))
        let monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { event in
            let (dy, py, inverted) = (event.scrollingDeltaY, event.hasPreciseScrollingDeltas, event.isDirectionInvertedFromDevice)
            log.notice("input-click: scroll seen scrollingDeltaY=\(dy) precise=\(py) invertedFromDevice=\(inverted)")
        }
        session.sendInput([
            .move(x: parts[0], y: parts[1]),
            .button(down: true, x: parts[0], y: parts[1]), .button(down: false, x: parts[0], y: parts[1]),
        ])
        try? await Task.sleep(for: .milliseconds(400))
        log.notice("input-click: cursor after click=\(NSStringFromPoint(CGEvent(source: nil)?.location ?? .zero), privacy: .public)")
        for dy: Float in [60, -60] {
            session.sendInput([.scroll(dx: 0, dy: dy)])
            log.notice("input-click: sent scroll dy=\(dy)")
            try? await Task.sleep(for: .milliseconds(600))
        }
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}
#endif
