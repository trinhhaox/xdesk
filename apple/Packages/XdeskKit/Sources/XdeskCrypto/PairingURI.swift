import Foundation

/// URI trong QR ghép đôi: `xdesk://pair?h=<host pub b64url>&t=<token b64url>&a=<host:port>[&a=...]`.
public struct PairingURI: Sendable, Equatable, Redacted {
    public static let maxAddresses = 4
    public static let maxAddressLength = 255

    public let hostPublicKey: [UInt8]
    public let token: [UInt8]
    /// `host:port` (IPv6 dạng `[addr]:port`), 1…4 địa chỉ ứng viên theo thứ tự ưu tiên.
    public let addresses: [String]

    public init(hostPublicKey: [UInt8], token: [UInt8], addresses: [String]) throws {
        guard hostPublicKey.count == 32, token.count == PairingToken.length,
              (1...Self.maxAddresses).contains(addresses.count),
              addresses.allSatisfy(HostPortAddress.isValid) else { throw CryptoError.invalidPairingURI }
        self.hostPublicKey = hostPublicKey
        self.token = token
        self.addresses = addresses
    }

    /// `token` được so sánh hằng thời gian.
    public static func == (lhs: PairingURI, rhs: PairingURI) -> Bool {
        ConstantTime.equals(lhs.token, rhs.token) && ConstantTime.equals(lhs.hostPublicKey, rhs.hostPublicKey)
            && lhs.addresses == rhs.addresses
    }

    public var string: String {
        var components = URLComponents()
        components.scheme = "xdesk"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "h", value: Base64URL.encode(hostPublicKey)),
            URLQueryItem(name: "t", value: Base64URL.encode(token)),
        ] + addresses.map { URLQueryItem(name: "a", value: $0) }
        return components.string ?? ""
    }

    public static func parse(_ text: String) throws -> PairingURI {
        guard let components = URLComponents(string: text), components.scheme == "xdesk", components.host == "pair",
              components.path.isEmpty else { throw CryptoError.invalidPairingURI }
        let items = components.queryItems ?? []
        let hosts = items.filter { $0.name == "h" }.compactMap(\.value)
        let tokens = items.filter { $0.name == "t" }.compactMap(\.value)
        guard hosts.count == 1, tokens.count == 1,
              let hostKey = Base64URL.decode(hosts[0]), let token = Base64URL.decode(tokens[0])
        else { throw CryptoError.invalidPairingURI }
        return try PairingURI(
            hostPublicKey: hostKey, token: token, addresses: items.filter { $0.name == "a" }.compactMap(\.value))
    }
}
