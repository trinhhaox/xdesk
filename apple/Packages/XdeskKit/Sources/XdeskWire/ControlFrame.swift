/// Loại frame trên kênh điều khiển TCP.
public enum ControlFrameKind: UInt8, Sendable, CaseIterable {
    case handshake = 0x01
    case control = 0x02
    case bulk = 0x03
    case mediaOverTcp = 0x04
}

/// Một frame điều khiển: `u32 len | u8 kind | payload[len-1]` (`len` gồm cả byte kind).
public struct ControlFrame: Sendable, Equatable {
    /// `len` tối đa (1 MiB).
    public static let maxLength = 1 << 20
    /// Chunk tối đa của frame `bulk`.
    public static let maxBulkPayload = 64 * 1024

    public let kind: ControlFrameKind
    public let payload: [UInt8]

    public init(kind: ControlFrameKind, payload: [UInt8]) {
        self.kind = kind
        self.payload = payload
    }

    /// `extraBulkAllowance`: byte thêm được phép trên payload bulk (tag AEAD 16 B khi kênh đã mã hoá).
    func validate(extraBulkAllowance: Int = 0) throws {
        if payload.count + 1 > Self.maxLength { throw WireError.frameTooLarge(payload.count + 1) }
        if kind == .bulk, payload.count > Self.maxBulkPayload + extraBulkAllowance { throw WireError.payloadTooLarge(payload.count) }
    }
}
