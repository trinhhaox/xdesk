import Foundation
import Network
import XdeskCrypto

extension ControlConnection {
    /// Bọc một kết nối đã `ready` đi qua usbmuxd. Luôn là kênh mã hoá: bắt tay Noise như Wi-Fi, không có đường tắt.
    public static func adoptUsbTunnel(_ connection: NWConnection, onClose: (@Sendable () -> Void)? = nil) -> ControlConnection {
        ControlConnection(connection: connection, encrypted: true, isUsbTunnel: true, onClose: onClose)
    }

    /// Viewer (TCP-server, iPhone/iPad): nhận kết nối đến từ `NWListener` loopback, khởi động và chờ `ready`.
    public static func acceptUsbTunnel(_ connection: NWConnection) async throws -> ControlConnection {
        let conn = adoptUsbTunnel(connection)
        try await conn.start()
        return conn
    }

    /// Phía TCP-client (Mac, host): báo khoá công khai của mình để viewer (TCP-server, iPhone) chọn khoá IK. Không phải xác thực.
    public func sendUsbHello(hostPublicKey: [UInt8]) async throws {
        try await sendHandshake(.usbHello(hostPublicKey))
    }

    /// Phía TCP-server (viewer): đọc lời chào đầu tiên của host; bất cứ thứ gì khác → đóng kết nối.
    public func receiveUsbHello() async throws -> [UInt8] {
        guard case .usbHello(let key) = try await receiveHandshake() else {
            close()
            throw TransportError.protocolViolation("cần usbHello")
        }
        return key
    }
}
