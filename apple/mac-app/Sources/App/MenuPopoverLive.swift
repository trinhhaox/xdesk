import AppKit
import SwiftUI
import XdeskTransport

/// Quyền và địa chỉ mạng do hệ thống đổi ngoài tầm quan sát của SwiftUI: đọc lại mỗi lần popover mở và định kỳ khi đang mở.
struct SystemSnapshot: Equatable {
    var screenRecording = PermissionsCheck.hasScreenRecording
    var accessibility = AccessibilityPermission.isGranted
    var lanAddress: String? = LocalAddress.primaryIPv4()
    var tailscaleAddress: String? = TailscaleDetector.current() ?? InterfaceFilter.tailscaleInterfaces().first?.address
}

/// Popover thật: ghép trạng thái từ các controller (quan sát được) với `SystemSnapshot` (đọc lại khi mở).
struct MenuPopoverLive: View {
    let host: HostController
    let viewer: ViewerController
    let pairing: PairingCoordinator
    let agent: AgentController
    let updater: UpdaterController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    /// Đóng bảng thanh menu trước khi mở cửa sổ/Cài đặt hệ thống, để bảng không che lên chúng.
    @Environment(\.dismiss) private var dismiss
    @State private var system = SystemSnapshot()
    private let ticker = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        MenuPopoverView(state: state, actions: actions)
            .onAppear { system = SystemSnapshot() }
            .onReceive(ticker) { _ in refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refresh() }
    }

    private func refresh() {
        let fresh = SystemSnapshot()
        if fresh != system { system = fresh }
    }

    private var port: UInt16? { if case .listening(let port) = host.status { port } else { nil } }

    private var state: PopoverState {
        let missing = PermissionKind.missing(
            screenRecording: system.screenRecording, accessibility: system.accessibility, inputMonitoringNeeded: agent.inputMonitorMissing)
        var failure: String?
        if case .failed(let message) = host.status { failure = message }
        return PopoverState(
            pill: .evaluate(isHosting: host.isHosting, failed: failure != nil, missing: missing),
            isHosting: host.isHosting,
            errorMessage: missing.contains(.screenRecording) ? nil : failure,
            missing: missing,
            sessions: host.activeViewers.map { .init(id: $0.id, info: $0.info) },
            lanText: system.lanAddress.map { address in port.map { EndpointFormat.hostPort(address, $0) } ?? address },
            tailscaleText: TailscaleLine.text(allowed: host.allowTailscale, address: system.tailscaleAddress, port: port),
            usb: host.usb.devices.map { .init(id: $0.deviceID, label: $0.shortSerial) },
            usbMessage: host.usbMessage,
            secureInput: host.secureInputActive,
            updateVersion: updater.pendingVersion,
            canCheckUpdates: updater.canCheckForUpdates,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }

    private var actions: PopoverActions {
        PopoverActions(
            toggleSharing: { [host] in Task { host.isHosting ? await host.stop() : await host.start() } },
            disconnect: { [host] id in Task { await host.disconnect(sessionId: id) } },
            openPermission: { kind in
                switch kind {
                case .screenRecording: PermissionsCheck.requestScreenRecording()
                case .accessibility: AccessibilityPermission.requestPrompt()
                case .inputMonitoring: break
                }
                dismiss()
                if let url = kind.settingsURL { NSWorkspace.shared.open(url) }
            },
            pairNewDevice: { [pairing] in dismiss(); Task { await pairing.showQrWindow() } },
            showPairedDevices: { [pairing] in dismiss(); pairing.showDevicesWindow() },
            connectToMac: {
                dismiss()
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: ViewerBrowserWindow.id)
            },
            connectUsb: { [host] id in
                guard let device = host.usb.devices.first(where: { $0.deviceID == id }) else { return }
                Task { await host.connectUsb(to: device) }
            },
            openSettings: {
                dismiss()
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            },
            checkForUpdates: { [updater] in dismiss(); updater.checkForUpdates() },
            quit: { NSApplication.shared.terminate(nil) },
            relaunch: { AppRelauncher.relaunch() })
    }
}
