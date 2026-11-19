import Foundation
import Network
import Testing
import XdeskWire
@testable import XdeskTransport

@Suite struct ClipboardTransferTests {
    private func receiveTransfer(on host: ControlConnection, header expected: ClipData) async throws -> [UInt8] {
        guard case .message(let envelope) = try await host.nextInbound(), case .clipData(let header) = envelope.message else {
            Issue.record("cần clip.data trước")
            return []
        }
        #expect(header == expected)
        var data: [UInt8] = []
        while data.count < Int(header.size) {
            guard case .bulk(let chunk) = try await host.nextInbound() else {
                Issue.record("cần frame bulk")
                break
            }
            #expect(chunk.count <= ControlFrame.maxBulkPayload)
            data += chunk
        }
        return data
    }

    @Test(.timeLimit(.minutes(1))) func maxSizeTransferCrossesEncryptedChannelIntact() async throws {
        let rig = try await SecureRig.make()
        let (viewer, host) = try await rig.pairWithQr()
        let payload = (0..<ClipLimits.maxBytes).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
        let header = ClipData(kind: .image, size: UInt32(payload.count), hash: String(repeating: "a", count: 64))
        async let received = receiveTransfer(on: host, header: header)
        try await viewer.sendClipData(header, payload: payload)
        #expect(try await received == payload)
        try await viewer.send(.ping(Ping(t0: 5)), id: 9)
        #expect(try await host.nextInbound() == .message(ControlEnvelope(id: 9, message: .ping(Ping(t0: 5)))))
        await rig.stop()
    }

    @Test(.timeLimit(.minutes(1))) func sizeMismatchIsRefusedBeforeSending() async throws {
        let rig = try await SecureRig.make()
        let (viewer, _) = try await rig.pairWithQr()
        let header = ClipData(kind: .text, size: 5, hash: String(repeating: "a", count: 64))
        await #expect(throws: (any Error).self) { try await viewer.sendClipData(header, payload: [1, 2]) }
        await rig.stop()
    }
}

@Suite struct InterfaceFilterTests {
    private func v4(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> NWEndpoint {
        .hostPort(host: .ipv4(IPv4Address(Data([a, b, c, d])) ?? .loopback), port: 47800)
    }

    @Test func recognisesTailscaleRanges() {
        #expect(InterfaceFilter.isTailscale(v4(100, 64, 0, 1)))
        #expect(InterfaceFilter.isTailscale(v4(100, 127, 255, 254)))
        #expect(!InterfaceFilter.isTailscale(v4(100, 63, 255, 255)))
        #expect(!InterfaceFilter.isTailscale(v4(100, 128, 0, 1)))
        #expect(!InterfaceFilter.isTailscale(v4(192, 168, 1, 5)))
        #expect(!InterfaceFilter.isTailscale(v4(127, 0, 0, 1)))
    }

    @Test func recognisesTailscaleUlaAndMappedV4() {
        var ula = [UInt8](repeating: 0, count: 16)
        ula.replaceSubrange(0..<6, with: [0xFD, 0x7A, 0x11, 0x5C, 0xA1, 0xE0])
        ula[15] = 9
        #expect(InterfaceFilter.isTailscale(ipv6: ula))
        ula[5] = 0xE1
        #expect(!InterfaceFilter.isTailscale(ipv6: ula))
        let mapped: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF, 100, 100, 1, 2]
        #expect(InterfaceFilter.isTailscale(ipv6: mapped))
        #expect(!InterfaceFilter.isTailscale(ipv6: [0xFD, 0x00] + [UInt8](repeating: 0, count: 14)))
    }

    @Test func tailscaleIsRejectedUnlessAllowed() {
        #expect(!InterfaceFilter.allows(v4(100, 90, 1, 1), allowTailscale: false))
        #expect(InterfaceFilter.allows(v4(100, 90, 1, 1), allowTailscale: true))
        #expect(InterfaceFilter.allows(v4(192, 168, 1, 5), allowTailscale: false))
    }
}

#if DEBUG
@Suite struct TailscaleGateTests {
    /// Coi mọi kết nối loopback là "đến từ Tailscale" để thử cổng lọc bằng TCP thật (máy test không bắt buộc có Tailscale).
    private func listener() -> ControlListener {
        ControlListener(security: testSecurity, tailscaleClassifier: { _ in true })
    }

    @Test(.timeLimit(.minutes(1))) func tailscaleConnectionIsRejectedWhileSettingIsOff() async throws {
        let l = listener()
        let port = try await l.start()
        let conn = try await ControlConnection.connect(host: "127.0.0.1", port: port, security: testSecurity)
        _ = try? await conn.send(.ping(Ping(t0: 1)))
        let closed = await eventually(seconds: 3) { (try? await conn.nextInbound()) == nil }
        #expect(closed)
        #expect(await l.activeViewers == 0)
        await l.stop()
    }

    @Test(.timeLimit(.minutes(1))) func tailscaleConnectionIsAcceptedOnceSettingIsOn() async throws {
        let l = listener()
        await l.setAllowTailscale(true)
        let port = try await l.start()
        let conn = try await ControlConnection.connect(host: "127.0.0.1", port: port, security: testSecurity)
        var iterator = l.connections.makeAsyncIterator()
        let accepted = await iterator.next()
        #expect(accepted != nil)
        await conn.close()
        await l.stop()
    }
}
#endif
