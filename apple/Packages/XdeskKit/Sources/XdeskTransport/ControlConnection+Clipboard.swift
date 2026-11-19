import Foundation
import XdeskWire

extension ControlConnection {
    /// Gửi một lần truyền clipboard: message `clip.data` rồi các frame bulk ≤ 64 KiB, mã hoá và ghi trong MỘT lượt
    /// (không có message khác chen giữa, thứ tự nonce = thứ tự byte) nên bên nhận ghép chunk theo thứ tự đến.
    public func sendClipData(_ header: ClipData, payload: [UInt8]) async throws {
        guard !closed else { throw TransportError.connectionClosed }
        guard payload.count == Int(header.size), payload.count <= ClipLimits.maxBytes else { throw WireError.invalidField("clip.data.size") }
        var out = try wireBytes(for: ControlFrame(
            kind: .control, payload: try ControlMessageCodec.encode(ControlEnvelope(id: takeNextId(), message: .clipData(header)))))
        var offset = 0
        while offset < payload.count {
            let end = min(offset + ControlFrame.maxBulkPayload, payload.count)
            out += try wireBytes(for: ControlFrame(kind: .bulk, payload: Array(payload[offset..<end])))
            offset = end
        }
        try await write(out)
    }
}
