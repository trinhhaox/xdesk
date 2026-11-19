import Foundation
import Testing
import XdeskWire
@testable import Xdesk

@Suite struct PopoverLogicTests {
    @Test func pillPrioritisesMissingScreenRecording() {
        #expect(StatusPill.evaluate(isHosting: false, failed: true, missing: [.screenRecording]) == .needsPermission)
        #expect(StatusPill.evaluate(isHosting: true, failed: false, missing: [.accessibility]) == .sharing)
        #expect(StatusPill.evaluate(isHosting: false, failed: false, missing: []) == .stopped)
        #expect(StatusPill.evaluate(isHosting: false, failed: true, missing: []) == .failed)
    }

    @Test func permissionRowsListOnlyWhatIsMissing() {
        #expect(PermissionKind.missing(screenRecording: true, accessibility: true, inputMonitoringNeeded: false).isEmpty)
        #expect(PermissionKind.missing(screenRecording: false, accessibility: false, inputMonitoringNeeded: true) == [.screenRecording, .accessibility, .inputMonitoring])
        for kind in PermissionKind.allCases {
            #expect(kind.settingsURL?.scheme == "x-apple.systempreferences")
            #expect(!kind.reason.contains("›"))
        }
        #expect(PermissionKind.screenRecording.settingsURL?.absoluteString.hasSuffix("Privacy_ScreenCapture") == true)
    }

    @Test func portHasNoThousandsSeparator() {
        #expect(EndpointFormat.hostPort("127.0.0.1", 47810) == "127.0.0.1:47810")
    }

    @Test func tailscaleDetectedOnAnyInterfaceName() {
        let found = TailscaleDetector.firstAddress(in: [("en0", "192.168.1.5"), ("utun5", "100.76.38.107")])
        #expect(found == "100.76.38.107")
        #expect(TailscaleDetector.firstAddress(in: [("en0", "192.168.1.5"), ("utun1", "100.63.0.1"), ("utun2", "100.128.0.1")]) == nil)
        #expect(TailscaleDetector.firstAddress(in: [("bridge0", "100.100.1.1")]) == "100.100.1.1")
    }

    @Test func tailscaleLineStates() {
        #expect(TailscaleLine.text(allowed: false, address: nil, port: nil) == "Tailscale: tắt")
        #expect(TailscaleLine.text(allowed: true, address: nil, port: 47800) == "Tailscale: chưa bật trên máy này")
        #expect(TailscaleLine.text(allowed: true, address: "100.1.2.3", port: 47810) == "Tailscale 100.1.2.3:47810")
        #expect(TailscaleLine.text(allowed: false, address: "100.1.2.3", port: 47810).contains("đang tắt"))
    }

    @Test func viewerInfoDescribesModeAndTransport() {
        var config = DisplayConfig(w: 1024, h: 768, scale: 2, fps: 60, codec: .h264)
        #expect(ViewerSessionInfo.make(name: " iPad ", config: config, isUsb: false, isTailscale: false)
            == ViewerSessionInfo(name: "iPad", transport: .lan, modeLabel: "Mở rộng"))
        config.mode = .mirror
        config.mirrorFit = .touch
        let usb = ViewerSessionInfo.make(name: "", config: config, isUsb: true, isTailscale: true)
        #expect(usb.transport == .usb)
        #expect(usb.modeLabel == "Bản sao · Cảm ứng")
        #expect(usb.name == "Thiết bị chưa đặt tên")
        #expect(ViewerSessionInfo.make(name: "x", config: config, isUsb: false, isTailscale: true).transport == .tailscale)
    }
}
