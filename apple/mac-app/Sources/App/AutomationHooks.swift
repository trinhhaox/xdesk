#if DEBUG
import AppKit
import Foundation
import os

/// Chỉ build Debug: điều khiển app bằng tham số dòng lệnh để kiểm thử không cần bấm UI.
///   --auto-host                 bật host ngay
///   --auto-connect host:port    viewer tự kết nối (kèm --retina / --latency-overlay / --fullscreen)
///   --auto-connect bonjour      viewer kết nối tới host đầu tiên tìm thấy qua Bonjour
///   --disconnect-after <giây>   viewer tự ngắt (host vẫn chạy) → màn hình ảo phải biến mất
///   --quit-after <giây>         tự thoát
@MainActor
enum AutomationHooks {
    private static let log = Logger(subsystem: "vn.xox.xdesk", category: "automation")

    static func run(host: HostController, viewer: ViewerController) async {
        let args = CommandLine.arguments
        viewer.options.retina = args.contains("--retina")
        viewer.options.fullScreen = args.contains("--fullscreen")
        viewer.options.latencyOverlay = args.contains("--latency-overlay")
        if args.contains("--auto-host") {
            await host.start()
            log.notice("auto-host status: \(String(describing: host.status), privacy: .public)")
        }
        if let value = value(after: "--auto-connect", in: args) {
            await autoConnect(value, viewer: viewer)
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

    private static func autoConnect(_ value: String, viewer: ViewerController) async {
        try? await Task.sleep(for: .seconds(1))
        let target: ViewerTarget?
        if value == "bonjour" {
            viewer.startBrowsing()
            for _ in 0..<20 where viewer.hosts.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
            log.notice("bonjour hosts: \(viewer.hosts.map(\.name).joined(separator: ","), privacy: .public)")
            target = viewer.hosts.first.map { ViewerTarget.discovered($0) }
        } else {
            target = ViewerController.parseManual(value)
        }
        guard let target else { log.error("auto-connect: no target for \(value, privacy: .public)"); return }
        await viewer.connect(to: target, title: value)
        log.notice("auto-connect state: \(String(describing: viewer.session?.state), privacy: .public) error: \(viewer.errorMessage ?? "-", privacy: .public)")
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}
#endif
