import Foundation
import Testing
@testable import XdeskAgent

@Suite struct McpTokenTests {
    @Test func generatesUniqueUrlSafeTokenOf32Bytes() throws {
        let first = try McpToken.generate()
        let second = try McpToken.generate()
        #expect(first != second)
        #expect(first.count == 43)
        #expect(first.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    @Test func buildsClaudeCodeCommand() {
        #expect(McpToken.claudeCodeCommand(port: 47810, token: "abc")
            == #"claude mcp add --transport http xdesk http://127.0.0.1:47810/mcp --header "Authorization: Bearer abc""#)
    }
}
