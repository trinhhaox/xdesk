import Foundation
import Network
import Testing
import XdeskWire
@testable import XdeskTransport

#if DEBUG
let testSecurity = TransportSecurity.devPlaintext

actor ChannelBox {
    private(set) var channel: UdpMediaChannel?
    func set(_ c: UdpMediaChannel) { channel = c }
}

/// Mất gói xác định: bỏ lần gửi đầu của các (frameNo, fragIdx) chỉ định (`always` → bỏ mọi lần).
final class DropPolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Set<[UInt32]>
    private let always: Bool
    private var dropped = 0

    init(_ targets: [(UInt32, UInt16)], always: Bool = false) {
        pending = Set(targets.map { [$0.0, UInt32($0.1)] })
        self.always = always
    }

    var droppedCount: Int { lock.lock(); defer { lock.unlock() }; return dropped }

    func shouldDrop(_ p: MediaPacket) -> Bool {
        guard p.header.type == .video else { return false }
        lock.lock(); defer { lock.unlock() }
        let key = [p.header.frameNo, UInt32(p.header.fragIdx)]
        guard pending.contains(key) else { return false }
        if !always { pending.remove(key) }
        dropped += 1
        return true
    }
}

struct Timeout: Error {}

/// Thu event cho đến khi `pick` đủ `count` kết quả, hoặc quá hạn.
func collect<T: Sendable>(
    _ channel: UdpMediaChannel, count: Int, timeout: Duration = .seconds(10),
    pick: @escaping @Sendable (UdpMediaChannel.Event) -> T?
) async throws -> [T] {
    try await withThrowingTaskGroup(of: [T].self) { group in
        let events = channel.events
        group.addTask {
            var out: [T] = []
            for await event in events {
                if let v = pick(event) { out.append(v) }
                if out.count >= count { break }
            }
            return out
        }
        group.addTask { try await Task.sleep(for: timeout); throw Timeout() }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw Timeout() }
        return first
    }
}

func pattern(size: Int, seed: UInt8) -> [UInt8] { (0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) } }

let testDisplay = DisplayConfig(w: 1920, h: 1200, scale: 2, fps: 60, codec: .h264)

/// Dựng một phiên điều khiển loopback hoàn chỉnh: host + viewer đã bắt tay, trả cổng UDP.
struct ControlPair {
    let listener: ControlListener
    let hostConnection: ControlConnection
    let viewer: ControlConnection
    let host: HostHandshakeResult
    let viewerResult: ViewerHandshakeResult
    let hostChannel: UdpMediaChannel
}

func makeControlPair(streamId: UInt16 = 7) async throws -> ControlPair {
    let listener = ControlListener(security: testSecurity)
    let port = try await listener.start(loopbackOnly: true)
    let box = ChannelBox()
    let hostSide = Task { () -> (ControlConnection, HostHandshakeResult) in
        for await conn in listener.connections {
            let result = try await conn.performHostHandshake(caps: [.h264, .mediaOverTcp], sessionId: "s-test") { _, _ in
                let channel = try await UdpMediaChannel.listen(streamId: streamId)
                await box.set(channel)
                return DisplayReady(udpPort: await channel.localPort, streamId: streamId)
            }
            return (conn, result)
        }
        throw TransportError.connectionClosed
    }
    let viewer = try await ControlConnection.connect(host: "127.0.0.1", port: port, security: testSecurity)
    let viewerResult = try await viewer.performViewerHandshake(name: "Test Viewer", caps: [.h264, .hevc], display: testDisplay)
    let (hostConnection, host) = try await hostSide.value
    guard let hostChannel = await box.channel else { throw TransportError.noPeer }
    return ControlPair(listener: listener, hostConnection: hostConnection, viewer: viewer, host: host, viewerResult: viewerResult, hostChannel: hostChannel)
}
#endif
