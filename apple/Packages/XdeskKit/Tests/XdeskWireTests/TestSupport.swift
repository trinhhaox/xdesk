import Foundation
import Testing
@testable import XdeskWire

/// RNG xác định (SplitMix64) cho test mất gói/fuzz.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func bytes(count: Int) -> [UInt8] { (0..<count).map { _ in UInt8.random(in: 0...255, using: &self) } }
}

typealias JSONDict = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) throws -> String { try #require(self[key] as? String) }
    func int(_ key: String) throws -> Int { try #require((self[key] as? NSNumber)?.intValue) }
    func float(_ key: String) throws -> Float { try #require((self[key] as? NSNumber)?.floatValue) }
    func bool(_ key: String) throws -> Bool { try #require(self[key] as? Bool) }
    func list(_ key: String) throws -> [JSONDict] { try #require(self[key] as? [JSONDict]) }
    func bytes(_ key: String) throws -> [UInt8] { try #require(WireHex.decode(try str(key))) }
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

/// Khẳng định `body` ném đúng mã lỗi `code`.
func expectWireError(_ code: String, sourceLocation: SourceLocation = #_sourceLocation, _ body: () throws -> Void) {
    do {
        try body()
        Issue.record("expected \(code), got success", sourceLocation: sourceLocation)
    } catch let error as WireError {
        #expect(error.code == code, sourceLocation: sourceLocation)
    } catch {
        Issue.record("unexpected error \(error)", sourceLocation: sourceLocation)
    }
}

/// Nhãn vector (trường `name`) để thông báo lỗi chỉ rõ ca nào hỏng.
func label(_ vector: JSONDict) -> Comment { Comment(rawValue: vector["name"] as? String ?? "?") }
