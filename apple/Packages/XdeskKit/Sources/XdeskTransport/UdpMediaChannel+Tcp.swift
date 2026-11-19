import Foundation
import XdeskWire

extension UdpMediaChannel {
    /// Kênh media chỉ đi qua MediaOverTcp (kind 0x04 của kênh control đã mã hoá): không mở socket UDP, không khoá UDP riêng.
    /// Dùng cho đường hầm USB (usbmux chỉ có TCP). `send` đưa gói ra kênh control; gói nhận được đẩy vào bằng `ingest`.
    /// TCP có thứ tự và tin cậy nên không NACK; sống/chết của liên kết do chính kết nối TCP quyết định (không có `linkLost`).
    public static func overTcp(
        streamId: UInt16, isViewer: Bool, send: @escaping @Sendable (MediaPacket) async throws -> Void
    ) async -> UdpMediaChannel {
        let channel = UdpMediaChannel(streamId: streamId, allowedPeerHost: nil, keys: nil)
        await channel.configureTcpOnly(isViewer: isViewer, send: send)
        return channel
    }

    private func configureTcpOnly(isViewer: Bool, send: @escaping @Sendable (MediaPacket) async throws -> Void) {
        self.isViewer = isViewer
        tcpSink = send
        linkTimeoutMs = Int.max
        if isViewer { startPolling() }
        startMaintenance()
    }
}
