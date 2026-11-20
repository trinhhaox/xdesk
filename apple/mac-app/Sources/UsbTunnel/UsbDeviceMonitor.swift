import Foundation
import Observation
import os

/// Theo dõi iPhone/iPad cắm cáp qua usbmuxd để menu hiện ngay (sự kiện `Attached` tới trong vài chục ms; thử nối lại usbmuxd nếu rớt).
@MainActor
@Observable
final class UsbDeviceMonitor {
    enum Status: Equatable {
        case stopped
        case listening
        /// usbmuxd chưa sẵn sàng/đã rớt; đang thử lại.
        case retrying(String)
    }

    private(set) var devices: [UsbDevice] = []
    private(set) var status: Status = .stopped

    @ObservationIgnored private let client: UsbmuxClient
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "vn.xox.xdesk", category: "usb-monitor")

    init(client: UsbmuxClient = UsbmuxClient()) { self.client = client }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
        devices = []
        status = .stopped
    }

    private func run() async {
        var delaySeconds = 1.0
        while !Task.isCancelled {
            do {
                for try await event in client.listen() {
                    status = .listening
                    delaySeconds = 1
                    apply(event)
                }
                status = .retrying(String(localized: "usbmuxd đã đóng kết nối"))
            } catch {
                status = .retrying(error.localizedDescription)
                log.error("usbmuxd listen: \(error.localizedDescription, privacy: .public)")
            }
            devices = []
            try? await Task.sleep(for: .seconds(delaySeconds))
            delaySeconds = min(5, delaySeconds * 2)
        }
    }

    func apply(_ event: UsbmuxEvent) {
        switch event {
        case .listening:
            break
        case .attached(let device):
            devices.removeAll { $0.deviceID == device.deviceID }
            devices.append(device)
        case .detached(let id):
            devices.removeAll { $0.deviceID == id }
        }
    }
}
