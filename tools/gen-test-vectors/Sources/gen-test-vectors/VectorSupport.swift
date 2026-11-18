import Foundation
import XdeskWire

typealias JSONObject = [String: Any]

func hex(_ bytes: [UInt8]) -> String { WireHex.encode(bytes) }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("gen-test-vectors: \(message)\n".utf8))
    exit(1)
}

func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
func be32(_ v: UInt32) -> [UInt8] { be16(UInt16(v >> 16)) + be16(UInt16(v & 0xFFFF)) }

/// Chạy `body` và đảm bảo nó ném đúng mã lỗi `expected` (tự kiểm vector không lệch decoder).
func expectError(_ name: String, _ expected: String, _ body: () throws -> Void) {
    do {
        try body()
        fail("\(name): expected error \(expected) but decode succeeded")
    } catch let error as WireError {
        if error.code != expected { fail("\(name): expected \(expected), got \(error.code)") }
    } catch {
        fail("\(name): unexpected error \(error)")
    }
}

func write(_ object: JSONObject, to url: URL) {
    do {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: url)
        print("wrote \(url.path)")
    } catch {
        fail("write \(url.lastPathComponent): \(error)")
    }
}
