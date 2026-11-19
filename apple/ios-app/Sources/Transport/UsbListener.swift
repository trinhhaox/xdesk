import Foundation
import Network
import XdeskTransport
import os

/// Nghe cổng cố định `UsbTunnel.devicePort` (47801) để Mac nối vào qua cáp USB (usbmuxd). iPhone/iPad là TCP-server nhưng vẫn là
/// initiator của Noise. Chỉ nhận kết nối từ loopback của chính thiết bị (usbmuxd đưa gói vào qua đó); nguồn khác bị đóng ngay,
/// nên cổng này không lộ ra Wi-Fi. Mỗi lần chỉ một kết nối đang bắt tay.
@MainActor
final class UsbListener {
    private let onTunnel: @MainActor (ControlConnection) async -> Void
    private let queue = DispatchQueue(label: "xdesk.usb.listener")
    private let log = Logger(subsystem: "vn.xox.xdesk", category: "usb-listener")
    private var listener: NWListener?
    private var busy = false

    init(onTunnel: @escaping @MainActor (ControlConnection) async -> Void) { self.onTunnel = onTunnel }

    var isListening: Bool { listener != nil }

    func start() {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: UsbTunnel.devicePort) else { return }
        do {
            let listener = try NWListener(using: .tcp, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                guard Self.isLoopback(connection.endpoint) else { connection.cancel(); return }
                Task { @MainActor in await self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    Task { @MainActor in self?.handleFailure(error) }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            log.error("không mở được cổng USB \(UsbTunnel.devicePort): \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleFailure(_ error: NWError) {
        log.error("listener USB hỏng: \(error.localizedDescription, privacy: .public)")
        stop()
    }

    private func accept(_ connection: NWConnection) async {
        guard !busy else { connection.cancel(); return }
        busy = true
        defer { busy = false }
        do {
            let tunnel = try await ControlConnection.acceptUsbTunnel(connection)
            await onTunnel(tunnel)
        } catch {
            log.error("đường hầm USB lỗi: \(error.localizedDescription, privacy: .public)")
            connection.cancel()
        }
    }

    nonisolated static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address.isLoopback
        case .ipv6(let address): return address.isLoopback
        case .name: return false
        @unknown default: return false
        }
    }
}
