/// Cửa sổ chống phát lại 1024 gói (bitmap vòng) cho bộ đếm nonce UDP trong một epoch.
struct ReplayWindow: Sendable {
    enum Verdict: Equatable { case fresh, duplicate, tooOld }

    static let size: UInt64 = 1024
    private var highest: UInt64?
    private var bits = [UInt64](repeating: 0, count: Int(size) / 64)

    /// Không thay đổi trạng thái; chỉ gọi `accept` sau khi gói đã xác thực AEAD thành công.
    func verdict(for counter: UInt64) -> Verdict {
        guard let highest, counter <= highest else { return .fresh }
        if highest - counter >= Self.size { return .tooOld }
        return isSet(counter) ? .duplicate : .fresh
    }

    mutating func accept(_ counter: UInt64) {
        if let highest, counter > highest {
            let advance = counter - highest
            if advance >= Self.size {
                bits = [UInt64](repeating: 0, count: bits.count)
            } else {
                for step in 1...advance { clear(highest + step) }
            }
            self.highest = counter
        } else if highest == nil {
            highest = counter
        }
        set(counter)
    }

    private func isSet(_ counter: UInt64) -> Bool {
        let slot = Int(counter % Self.size)
        return bits[slot / 64] & (1 << UInt64(slot % 64)) != 0
    }

    private mutating func set(_ counter: UInt64) {
        let slot = Int(counter % Self.size)
        bits[slot / 64] |= 1 << UInt64(slot % 64)
    }

    private mutating func clear(_ counter: UInt64) {
        let slot = Int(counter % Self.size)
        bits[slot / 64] &= ~(1 << UInt64(slot % 64))
    }
}
