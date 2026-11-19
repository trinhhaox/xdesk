import Foundation
import XdeskWire

/// Kết quả handshake phía viewer.
public struct ViewerHandshakeResult: Sendable, Equatable {
    public let sessionId: String
    public let caps: Capabilities
    public let ready: DisplayReady
}

/// Kết quả handshake phía host.
public struct HostHandshakeResult: Sendable, Equatable {
    public let peer: Hello
    public let sessionId: String
    public let caps: Capabilities
    public let display: DisplayConfig
    public let ready: DisplayReady
}

extension ControlConnection {
    public static let handshakeTimeoutSeconds = 10.0

    /// Viewer: hello → welcome → display.config → display.ready.
    public func performViewerHandshake(
        name: String, caps: Capabilities, display: DisplayConfig
    ) async throws -> ViewerHandshakeResult {
        try await withDeadline(seconds: Self.handshakeTimeoutSeconds) {
            let helloId = try await send(.hello(Hello(ver: ProtocolVersion.current.string, caps: caps.rawValue, name: name)))
            let welcome = try await expect(id: helloId) { if case .welcome(let w) = $0 { w } else { nil } }
            let configId = try await send(.displayConfig(display))
            let ready = try await expect(id: configId) { if case .displayReady(let r) = $0 { r } else { nil } }
            return ViewerHandshakeResult(
                sessionId: welcome.sessionId, caps: Capabilities(rawValue: welcome.caps).intersection(caps), ready: ready
            )
        }
    }

    /// Host: nhận hello (kiểm phiên bản) → welcome → nhận display.config (kiểm codec) →
    /// `prepareDisplay` (tạo kênh UDP, trả cổng) → display.ready. Từ chối bằng `reject` rồi ném lỗi.
    public func performHostHandshake(
        caps hostCaps: Capabilities,
        sessionId: String,
        prepareDisplay: @Sendable (Hello, DisplayConfig) async throws -> DisplayReady
    ) async throws -> HostHandshakeResult {
        try await withDeadline(seconds: Self.handshakeTimeoutSeconds) {
            var helloId: UInt32 = 0
            let hello = try await expect { envelope in
                if case .hello(let h) = envelope.message { helloId = envelope.id; return h }
                return nil
            }
            guard let version = ProtocolVersion(string: hello.ver), version.isCompatible(with: .current) else {
                try await rejectAndThrow(id: helloId, reason: Reject.reasonVersion, detail: "version \(hello.ver) not supported")
            }
            let common = Capabilities(rawValue: hello.caps).intersection(hostCaps)
            try await send(.welcome(Welcome(ver: ProtocolVersion.current.string, sessionId: sessionId, caps: common.rawValue)), id: helloId)

            var configId: UInt32 = 0
            let display = try await expect { envelope in
                if case .displayConfig(let c) = envelope.message { configId = envelope.id; return c }
                return nil
            }
            if display.codec == .hevc, !common.contains(.hevc) {
                try await rejectAndThrow(id: configId, reason: "codec", detail: "hevc not negotiated")
            }
            let ready = try await prepareDisplay(hello, display)
            try await send(.displayReady(ready), id: configId)
            return HostHandshakeResult(peer: hello, sessionId: sessionId, caps: common, display: display, ready: ready)
        }
    }

    private func rejectAndThrow(id: UInt32, reason: String, detail: String) async throws -> Never {
        _ = try? await send(.reject(Reject(reason: reason, detail: detail)), id: id)
        close()
        throw TransportError.rejected(reason: reason, detail: detail)
    }

    /// Đọc đến khi `pick` nhận ra message mong đợi. `reject` → lỗi; message khác → vi phạm giao thức.
    private func expect<T: Sendable>(_ pick: (ControlEnvelope) -> T?) async throws -> T {
        guard let inbound = try await nextInbound() else { throw TransportError.connectionClosed }
        guard case .message(let envelope) = inbound else { throw TransportError.protocolViolation("expected control message") }
        if case .reject(let r) = envelope.message { throw TransportError.rejected(reason: r.reason, detail: r.detail) }
        guard let value = pick(envelope) else { throw TransportError.protocolViolation("unexpected \(envelope.message.typeName)") }
        return value
    }

    private func expect<T: Sendable>(id: UInt32, _ pick: (ControlMessage) -> T?) async throws -> T {
        try await expect { envelope in envelope.id == id ? pick(envelope.message) : nil }
    }
}
