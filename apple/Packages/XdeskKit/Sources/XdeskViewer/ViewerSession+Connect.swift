import Foundation
import Network
import XdeskCrypto
import XdeskTransport
import XdeskWire

extension ViewerSession {
    /// Ghép đôi bằng QR: thử lần lượt các địa chỉ trong URI; ghim khoá host `h` trước khi gửi danh tính của viewer.
    public func pair(with uri: PairingURI, config: DisplayConfig) async {
        let targets = uri.addresses.compactMap(ViewerTarget.parse(address:))
        await connect(candidates: targets, config: config, auth: .qr(uri))
    }

    func openConnection(_ targets: [ViewerTarget]) async throws -> (ControlConnection, ViewerTarget) {
        var lastError: any Error = TransportError.connectionFailed("không có địa chỉ")
        for target in targets {
            do {
                switch target {
                case .discovered(let host): return (try await ControlConnection.connect(to: host.endpoint, security: security), target)
                case .manual(let host, let port): return (try await ControlConnection.connect(host: host, port: port, security: security), target)
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Chọn kiểu bắt tay từ `auth` + danh sách host đã biết.
    func authMode(for target: ViewerTarget, auth: ViewerAuth) async throws -> ViewerAuthMode {
        switch auth {
        case .qr(let uri): return .qr(uri)
        case .sas(let onCode): return .sas(onCode: onCode)
        case .automatic:
            guard let trust else { throw TransportError.pairingRequired }
            switch target {
            case .discovered(let host):
                switch await trust.state(of: host) {
                case .paired(let device): return .reconnect(hostKey: device.publicKey)
                case .keyChanged: throw TransportError.hostKeyMismatch
                case .unknown: throw TransportError.pairingRequired
                }
            case .manual(let host, let port):
                guard let device = await trust.device(address: "\(host):\(port)") else { throw TransportError.pairingRequired }
                return .reconnect(hostKey: device.publicKey)
            }
        }
    }

    /// Noise (nếu `.encrypted`) trước hello/welcome; ghi nhận host vào danh sách đã biết khi thành công.
    func authenticate(_ conn: ControlConnection, target: ViewerTarget, auth: ViewerAuth) async throws {
        guard security == .encrypted else { return }
        guard let trust else { throw TransportError.pairingRequired }
        let mode = try await authMode(for: target, auth: auth)
        let outcome: InitiatorOutcome
        do {
            outcome = try await conn.performInitiatorHandshake(identity: trust.identity, deviceName: deviceName, mode: mode)
        } catch TransportError.connectionClosed {
            // Host bỏ qua IK của khoá lạ bằng cách đóng im lặng: với host đã ghép, đó gần như chắc là bị thu hồi.
            guard case .reconnect(let hostKey) = mode else { throw TransportError.connectionClosed }
            refusedHostId = DeviceFingerprint.make(publicKey: hostKey)
            throw TransportError.reconnectRefused
        }
        await remember(outcome, target: target, trust: trust)
        connectedHostId = DeviceFingerprint.make(publicKey: outcome.hostKey)
        connectedHostKey = outcome.hostKey
        connectedHostName = outcome.hostName
    }

    /// Host báo đã thu hồi (thông điệp đã xác thực trên kênh mã hoá): xoá host khỏi danh sách đã biết.
    func forgetRevokedHost() async {
        guard let trust, let id = connectedHostId else { return }
        do { _ = try await trust.knownHosts.remove(id: id) } catch {
            log.error("không xoá được host đã thu hồi: \(error.localizedDescription, privacy: .public)")
        }
    }

    func remember(_ outcome: InitiatorOutcome, target: ViewerTarget?, trust: ViewerTrust) async {
        do {
            if outcome.method != .reconnect {
                try await trust.knownHosts.add(name: outcome.hostName, publicKey: outcome.hostKey, role: .host)
            }
            let id = DeviceFingerprint.make(publicKey: outcome.hostKey)
            try await trust.knownHosts.markSeen(id: id)
            if case .manual(let host, let port)? = target { try await trust.knownHosts.setLastAddress(id: id, "\(host):\(port)") }
        } catch {
            log.error("không lưu được host đã biết: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Nối kênh UDP với control để gửi `rekey.resync`.
    func wireResync(channel: UdpMediaChannel, connection: ControlConnection) async {
        await channel.setResyncSink { resync in
            do { _ = try await connection.send(.rekeyResync(resync)) } catch {
                // Kênh control đã đóng: phiên sắp kết thúc, không còn gì để đồng bộ.
            }
        }
    }
}

extension ViewerTarget {
    /// `host:port` hoặc `[IPv6]:port` (dạng địa chỉ trong QR). Sai định dạng → nil.
    public static func parse(address text: String) -> ViewerTarget? {
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            let host = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...]
            guard rest.hasPrefix(":"), let port = UInt16(rest.dropFirst()), port > 0 else { return nil }
            return .manual(host: host, port: port)
        }
        return parse(manual: text)
    }
}
