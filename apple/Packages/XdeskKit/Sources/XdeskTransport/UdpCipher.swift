import XdeskCrypto
import XdeskWire

/// Cặp cipher UDP (gửi + nhận) của một kênh media; chỉ `UdpMediaChannel` sở hữu, không copy được.
/// Gói gửi lại (đáp NACK) đi qua `seal` lần nữa nên luôn có counter mới.
struct UdpCipher: ~Copyable, Sendable {
    private var sender: DatagramSender
    private var receiver: DatagramReceiver

    init(keys: UdpKeys) {
        sender = DatagramSender(key: keys.send)
        receiver = DatagramReceiver(key: keys.receive)
    }

    var sendEpoch: UInt32 { sender.epoch }
    var receiveEpoch: UInt32 { receiver.epoch }
    var needsRekey: Bool { sender.needsRekey }

    mutating func rekey() throws { try sender.rekey() }

    mutating func resync(toEpoch epoch: UInt32) throws { try receiver.resync(toEpoch: epoch) }

    mutating func seal(_ packet: MediaPacket) throws -> [UInt8] {
        let bytes = try packet.encode()
        return try sender.seal(header: Array(bytes[..<MediaHeader.size]), payload: Array(bytes[MediaHeader.size...]))
    }

    mutating func open(_ datagram: [UInt8]) throws -> MediaPacket {
        let opened = try receiver.open(datagram)
        return try MediaPacket.decode(opened.header + opened.payload)
    }
}
