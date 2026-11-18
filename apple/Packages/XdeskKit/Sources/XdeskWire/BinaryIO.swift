/// Ghi số nguyên/float big-endian (network order) vào bộ đệm.
struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    init(capacity: Int = 0) { bytes.reserveCapacity(capacity) }

    mutating func u8(_ v: UInt8) { bytes.append(v) }

    mutating func u16(_ v: UInt16) {
        bytes.append(UInt8(truncatingIfNeeded: v >> 8))
        bytes.append(UInt8(truncatingIfNeeded: v))
    }

    mutating func u32(_ v: UInt32) {
        u16(UInt16(truncatingIfNeeded: v >> 16))
        u16(UInt16(truncatingIfNeeded: v))
    }

    mutating func f32(_ v: Float) { u32(v.bitPattern) }

    mutating func append(_ other: [UInt8]) { bytes.append(contentsOf: other) }
}

/// Đọc big-endian có kiểm tra biên; thiếu dữ liệu → ném `WireError.truncated`.
struct ByteReader {
    private let bytes: [UInt8]
    private(set) var offset: Int

    init(_ bytes: [UInt8], offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    var remaining: Int { bytes.count - offset }

    private mutating func advance(_ n: Int) throws -> Int {
        guard n >= 0, remaining >= n else { throw WireError.truncated(need: n, have: remaining) }
        defer { offset += n }
        return offset
    }

    mutating func u8() throws -> UInt8 { bytes[try advance(1)] }

    mutating func u16() throws -> UInt16 {
        let i = try advance(2)
        return UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
    }

    mutating func u32() throws -> UInt32 {
        let hi = try u16()
        let lo = try u16()
        return UInt32(hi) << 16 | UInt32(lo)
    }

    mutating func f32() throws -> Float { Float(bitPattern: try u32()) }

    mutating func take(_ n: Int) throws -> [UInt8] {
        let i = try advance(n)
        return Array(bytes[i..<i + n])
    }
}

/// Chuyển đổi hex cho test vectors và gỡ lỗi.
public enum WireHex {
    public static func encode(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef")
        var out = ""
        out.reserveCapacity(bytes.count * 2)
        for b in bytes {
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 0x0F)])
        }
        return out
    }

    /// Trả `nil` nếu chuỗi lẻ ký tự hoặc có ký tự không phải hex.
    public static func decode(_ hex: String) -> [UInt8]? {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
        }
        return out
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: c - 0x30
        case 0x61...0x66: c - 0x61 + 10
        case 0x41...0x46: c - 0x41 + 10
        default: nil
        }
    }
}
