import Foundation
import XdeskWire

extension ControlConnection {
    /// Gửi một mảnh tệp streaming: cặp nguyên tử `file.chunk` + frame `BULK` (≤ 64 KiB) trong một lượt ghi
    /// để không xen giữa với clipboard hay luồng gửi khác, trong khi vẫn cho phép `ping`/`cancel` chen giữa từng mảnh.
    public func sendFileBulkChunk(_ header: FileChunk, payload: [UInt8]) async throws {
        guard !closed else { throw TransportError.connectionClosed }
        guard !payload.isEmpty, payload.count == Int(header.size), payload.count <= ControlFrame.maxBulkPayload else {
            throw WireError.invalidField("file.chunk.size")
        }
        var out = try wireBytes(for: ControlFrame(
            kind: .control,
            payload: try ControlMessageCodec.encode(ControlEnvelope(id: takeNextId(), message: .fileChunk(header)))
        ))
        out += try wireBytes(for: ControlFrame(kind: .bulk, payload: payload))
        try await write(out)
    }
}
