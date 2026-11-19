import SwiftUI

/// Mục menu "iPhone/iPad cắm cáp USB": hiện thiết bị usbmuxd báo, nút "Phát qua USB" nối vào app Xdesk đang mở trên máy đó.
struct UsbMenuSection: View {
    let host: HostController

    var body: some View {
        if host.usb.devices.isEmpty {
            if case .retrying = host.usb.status { Text("USB: chưa nối được usbmuxd") }
        } else {
            ForEach(host.usb.devices) { device in
                Button("Phát qua USB tới iPhone/iPad …\(device.shortSerial)") { Task { await host.connectUsb(to: device) } }
                    .disabled(!host.isHosting)
            }
        }
        if let message = host.usbMessage { Text("USB: \(message)") }
    }
}
