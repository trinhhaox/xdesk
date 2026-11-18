import CryptoKit
import Foundation
import Testing
@testable import XdeskCrypto

typealias JSONDict = [String: Any]

enum Hex {
    static func decode(_ string: String) -> [UInt8]? {
        guard string.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let byte = UInt8(string[index..<next], radix: 16) else { return nil }
            out.append(byte)
            index = next
        }
        return out
    }

    static func encode(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
}

extension Dictionary where Key == String, Value == Any {
    func hex(_ key: String) throws -> [UInt8] { try #require(Hex.decode(try str(key))) }
    func optionalHex(_ key: String) throws -> [UInt8]? { self[key] == nil ? nil : try hex(key) }
    func str(_ key: String) throws -> String { try #require(self[key] as? String) }
    func int(_ key: String) throws -> Int { try #require((self[key] as? NSNumber)?.intValue) }
    func list(_ key: String) throws -> [JSONDict] { try #require(self[key] as? [JSONDict]) }
}

enum Vectors {
    /// `<repo>/protocol/test-vectors`, tính từ vị trí file này.
    static let directory: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("protocol/test-vectors", isDirectory: true)
    }()

    static func load(_ name: String) throws -> JSONDict {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        return try #require(try JSONSerialization.jsonObject(with: data) as? JSONDict)
    }
}

func privateKey(_ bytes: [UInt8]) throws -> Curve25519.KeyAgreement.PrivateKey {
    try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bytes)
}

func fixedKey(_ byte: UInt8) -> SymmetricKey { SymmetricKey(data: [UInt8](repeating: byte, count: 32)) }

/// `#expect` không nhận biểu thức dùng kiểu `~Copyable` (sender/receiver/handshake); dùng hàm thường này thay thế.
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == expected, sourceLocation: sourceLocation)
}

/// `#require(state.property)` không dùng được với kiểu `~Copyable`; đọc property ra trước rồi truyền vào đây.
func unwrap<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) throws -> T {
    try #require(value, sourceLocation: sourceLocation)
}
