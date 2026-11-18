#if DEBUG
import AppKit
import Foundation
import os
import XdeskInput
import XdeskViewer

/// Chỉ build Debug: điều khiển app bằng tham số dòng lệnh để kiểm thử không cần bấm UI.
///   --auto-host                 bật host ngay
///   --auto-connect host:port    viewer tự kết nối (kèm --retina / --latency-overlay / --fullscreen)
///   --auto-connect bonjour      viewer kết nối tới host đầu tiên tìm thấy qua Bonjour
///   --input-probe x,y           sau khi kết nối: gửi move tới (x,y) chuẩn hoá rồi log quyền Trợ năng + vị trí con trỏ thật
///   --input-click x,y           sau khi kết nối: click trái tại (x,y) chuẩn hoá rồi cuộn +60/-60; log vị trí con trỏ và delta cuộn thấy được ở app khác
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
