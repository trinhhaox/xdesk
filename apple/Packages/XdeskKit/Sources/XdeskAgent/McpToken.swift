import Foundation
import Security

public enum McpToken {
    public enum GenerationError: Error { case randomUnavailable(OSStatus) }

    /// 32 byte ngẫu nhiên từ CSPRNG hệ thống, mã hoá base64url (43 ký tự, không padding).
    public static func generate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw GenerationError.randomUnavailable(status) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Lệnh Claude Code; chứa token nên chỉ dùng để chép vào clipboard, không ghi log.
    public static func claudeCodeCommand(port: UInt16, token: String) -> String {
        "claude mcp add --transport http xdesk http://127.0.0.1:\(port)/mcp --header \"Authorization: Bearer \(token)\""
    }
}
