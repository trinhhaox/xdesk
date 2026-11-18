enum ConstantTime {
    /// So sánh hai dãy byte, thời gian không phụ thuộc vị trí byte khác nhau đầu tiên.
    static func equals(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    static func isAllZero(_ a: [UInt8]) -> Bool {
        var acc: UInt8 = 0
        for byte in a { acc |= byte }
        return acc == 0
    }
}
