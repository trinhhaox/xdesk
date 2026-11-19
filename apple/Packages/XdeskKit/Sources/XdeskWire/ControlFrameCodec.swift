/// Mã hoá/giải mã frame điều khiển. `len` sai → ném lỗi ngay khi đủ 4 byte đầu.
public enum ControlFrameCodec {
    public static func encode(_ frame: ControlFrame, extraBulkAllowance: Int = 0) throws -> [UInt8] {
        try frame.validate(extraBulkAllowance: extraBulkAllowance)
        var w = ByteWriter(capacity: frame.payload.count + 5)
        w.u32(UInt32(frame.payload.count + 1))
        w.u8(frame.kind.rawValue)
        w.append(frame.payload)
        return w.bytes
    }

    /// Giải mã một frame ở đầu `bytes`. Trả `nil` khi chưa đủ dữ liệu; ngược lại
    /// trả frame và số byte đã dùng.
    public static func decode(_ bytes: [UInt8], extraBulkAllowance: Int = 0) throws -> (frame: ControlFrame, consumed: Int)? {
        var r = ByteReader(bytes)
        guard r.remaining >= 5 else {
            if r.remaining >= 4 { _ = try checkedLength(&r) }
            return nil
        }
        let len = try checkedLength(&r)
        let rawKind = try r.u8()
        guard let kind = ControlFrameKind(rawValue: rawKind) else { throw WireError.unknownFrameKind(rawKind) }
        guard r.remaining >= len - 1 else { return nil }
        let frame = ControlFrame(kind: kind, payload: try r.take(len - 1))
        try frame.validate(extraBulkAllowance: extraBulkAllowance)
        return (frame, 4 + len)
    }

    private static func checkedLength(_ r: inout ByteReader) throws -> Int {
        let len = Int(try r.u32())
        guard len >= 1 else { throw WireError.invalidFrameLength(len) }
        guard len <= ControlFrame.maxLength else { throw WireError.frameTooLarge(len) }
        return len
    }
}

/// Bộ giải mã luồng TCP. Sau khi `next()` ném lỗi, kết nối phải bị đóng (không dùng tiếp).
public struct ControlFrameDecoder: Sendable {
    private var buffer: [UInt8] = []
    /// Đặt 16 khi kênh đã mã hoá (payload bulk = plaintext ≤ 64 KiB + tag).
    public var extraBulkAllowance = 0

    public init() {}

    public var bufferedCount: Int { buffer.count }

    public mutating func append(_ bytes: [UInt8]) { buffer.append(contentsOf: bytes) }

    public mutating func next() throws -> ControlFrame? {
        guard let (frame, consumed) = try ControlFrameCodec.decode(buffer, extraBulkAllowance: extraBulkAllowance) else { return nil }
        buffer.removeFirst(consumed)
        return frame
    }
}
