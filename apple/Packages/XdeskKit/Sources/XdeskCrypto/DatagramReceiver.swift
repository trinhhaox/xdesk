import CryptoKit

public struct OpenedDatagram: Sendable, Equatable {
    public let header: [UInt8]
    public let payload: [UInt8]
}

/// Phía nhận UDP: kiểm replay (cửa sổ 1024), xác thực AEAD rồi mới cập nhật trạng thái.
/// Chấp nhận epoch hiện tại, epoch ngay trước (gói đến muộn) và nhảy tới tối đa `maxEpochLookahead` epoch mới hơn
/// (khoá dẫn xuất thử, chỉ chuyển epoch khi tag xác thực được). Xa hơn → `unknownEpoch`; phiên phải đồng bộ lại qua kênh control.
/// `~Copyable`: bản sao sẽ có cửa sổ replay cũ, cho phép phát lại gói.
public struct DatagramReceiver: ~Copyable, Sendable {
    /// Số epoch tối đa bên gửi được phép bỏ qua (kể cả khi im lặng rekey theo giờ) mà bên nhận vẫn tự theo kịp.
    public static let maxEpochLookahead: UInt32 = 4
    public static let maxResyncGap: UInt32 = 64

    private struct Epoch: Sendable {
        var number: UInt32
        var key: SymmetricKey
        var window = ReplayWindow()
    }

    private var current: Epoch
    private var previous: Epoch?

    // Deinit tường minh: huỷ qua hàm của XdeskCrypto, không để module khác inline việc huỷ các kiểu nội bộ (lỗi liên kết Release).
    deinit {}

    public init(key: SymmetricKey) { current = Epoch(number: 0, key: key) }

    public var epoch: UInt32 { current.number }

    /// Kéo khoá nhận lên `target` khi bên gửi đã vượt cửa sổ nhìn trước. Chỉ gọi với epoch báo qua kênh control đã xác thực;
    /// `target` ≤ epoch hiện tại là không làm gì, chênh quá `maxResyncGap` bị từ chối (chặn CPU DoS).
    public mutating func resync(toEpoch target: UInt32) throws {
        guard target > current.number else { return }
        guard target - current.number <= Self.maxResyncGap else { throw CryptoError.unknownEpoch }
        var key = current.key
        for _ in 0..<(target - current.number) { key = KeySchedule.next(key) }
        previous = nil
        current = Epoch(number: target, key: key)
    }

    public mutating func open(_ datagram: [UInt8]) throws -> OpenedDatagram {
        let headerEnd = DatagramFormat.headerLength
        let bodyStart = headerEnd + DatagramFormat.nonceLength
        guard datagram.count >= bodyStart + DatagramFormat.tagLength else { throw CryptoError.datagramTooShort }
        let nonce = datagram[headerEnd..<bodyStart].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let epochNumber = UInt32(truncatingIfNeeded: nonce >> 32)
        let counter = nonce & 0xFFFF_FFFF

        var slot = try trialEpoch(for: epochNumber)
        switch slot.window.verdict(for: counter) {
        case .fresh: break
        case .duplicate: throw CryptoError.replayed
        case .tooOld: throw CryptoError.outsideReplayWindow
        }

        let header = Array(datagram[0..<headerEnd])
        let tagStart = datagram.count - DatagramFormat.tagLength
        let payload: [UInt8]
        do {
            let box = try ChaChaPoly.SealedBox(
                nonce: ChaChaNonce.make(counter: nonce), ciphertext: datagram[bodyStart..<tagStart], tag: datagram[tagStart...])
            payload = Array(try ChaChaPoly.open(box, using: slot.key, authenticating: header))
        } catch { throw CryptoError.authenticationFailed }

        slot.window.accept(counter)
        commit(slot)
        return OpenedDatagram(header: header, payload: payload)
    }

    /// Trạng thái epoch dùng để thử giải mã; chưa thay đổi gì ở `self`.
    private func trialEpoch(for epochNumber: UInt32) throws -> Epoch {
        if epochNumber == current.number { return current }
        if epochNumber > current.number, epochNumber - current.number <= Self.maxEpochLookahead {
            var key = current.key
            for _ in 0..<(epochNumber - current.number) { key = KeySchedule.next(key) }
            return Epoch(number: epochNumber, key: key)
        }
        if let previous, previous.number == epochNumber { return previous }
        throw CryptoError.unknownEpoch
    }

    /// Chỉ gọi sau khi tag đã xác thực.
    private mutating func commit(_ slot: Epoch) {
        if slot.number > current.number {
            // Epoch ngay trước epoch mới vẫn nhận gói muộn: giữ epoch cũ nếu liền kề, nếu không thì dẫn xuất lại (cửa sổ mới).
            previous = slot.number - current.number == 1 ? current : Epoch(number: slot.number - 1, key: Self.key(before: slot.number, from: current))
            current = slot
        } else if slot.number == current.number {
            current = slot
        } else {
            previous = slot
        }
    }

    private static func key(before target: UInt32, from epoch: Epoch) -> SymmetricKey {
        var key = epoch.key
        for _ in 0..<(target - 1 - epoch.number) { key = KeySchedule.next(key) }
        return key
    }
}
