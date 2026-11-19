import Foundation
import Testing

/// Build Release không được có đường plaintext: mọi chỗ nhắc `devPlaintext` trong mã nguồn (package + hai app)
/// phải nằm trong khối `#if DEBUG`. (Bản Release thật còn được kiểm bằng `swift build -c release`: case này không tồn tại ở đó.)
@Suite struct ReleaseSafetyTests {
    private static var appleRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    private static func swiftFiles(in directories: [String]) -> [URL] {
        directories.flatMap { dir -> [URL] in
            let root = appleRoot.appendingPathComponent(dir, isDirectory: true)
            let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            return (walker?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        }
    }

    /// Số dòng (1-based) nhắc `devPlaintext` ngoài `#if DEBUG`.
    static func unguardedMentions(in source: String) -> [Int] {
        var stack: [Bool] = []   // true = nhánh chỉ chạy khi DEBUG
        var found: [Int] = []
        for (index, raw) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#if") {
                stack.append(line == "#if DEBUG")
            } else if line.hasPrefix("#else") || line.hasPrefix("#elseif") {
                if !stack.isEmpty { stack[stack.count - 1] = false }
            } else if line.hasPrefix("#endif") {
                _ = stack.popLast()
            } else if line.contains("devPlaintext"), !line.hasPrefix("//"), !stack.contains(true) {
                found.append(index + 1)
            }
        }
        return found
    }

    @Test func devPlaintextOnlyExistsInsideDebugBlocks() throws {
        let files = Self.swiftFiles(in: ["Packages/XdeskKit/Sources", "mac-app/Sources", "ios-app/Sources"])
        #expect(files.count > 30)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(Self.unguardedMentions(in: source).isEmpty, "\(file.lastPathComponent) nhắc devPlaintext ngoài #if DEBUG")
        }
    }

    @Test func scannerCatchesAnUnguardedMention() {
        #expect(Self.unguardedMentions(in: "let a = 1\nlet x = TransportSecurity.devPlaintext\n") == [2])
        #expect(Self.unguardedMentions(in: "#if DEBUG\nlet x = .devPlaintext\n#else\nlet y = 2\n#endif\n").isEmpty)
        #expect(Self.unguardedMentions(in: "#if DEBUG\n#else\nlet x = .devPlaintext\n#endif\n") == [3])
    }
}
