import Foundation
import Network
import XdeskTransport

extension HostController {
    /// Mac nối vào app Xdesk trên iPhone/iPad qua cáp (usbmuxd). Mac là TCP-client nhưng vẫn là responder của Noise:
    /// bắt tay IK/ghép đôi y như Wi-Fi, quyền theo thiết bị đã ghép.
    func connectUsb(to device: UsbDevice) async {
        usbMessage = nil
        do {
            let tunnel = try await UsbmuxClient().connect(deviceID: device.deviceID, port: UsbTunnel.devicePort)
            try await adoptUsb(tunnel)
        } catch {
            usbMessage = error.localizedDescription
        }
    }

    /// Đưa một đường hầm đã nối (usbmuxd, hoặc loopback khi kiểm thử) vào luồng admit như kết nối Wi-Fi.
    func adoptUsb(_ tunnel: NWConnection) async throws {
        guard AppSecurity.current == .encrypted else {
            tunnel.cancel()
            throw TransportError.encryptionUnavailable
        }
        guard let listener = currentListener, let key = await security.hostPublicKey else {
            tunnel.cancel()
            throw TransportError.listenerFailed(String(localized: "hãy bật chia sẻ màn hình trước"))
        }
        try await listener.adoptUsbTunnel(tunnel, hostPublicKey: key)
    }

    /// Tự động forward cổng 47800 cho Android qua ADB khi cắm cáp USB (adb reverse tcp:47800 tcp:47800).
    @discardableResult
    func setupAndroidAdbReverse() async -> Bool {
        let adbCandidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb"
        ]
        guard let adb = adbCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = ["reverse", "tcp:\(HostController.preferredPort)", "tcp:\(HostController.preferredPort)"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
