import Testing
@testable import XdeskInput

@Suite struct TextEditDiffTests {
    @Test func appendOnlyInsertsSuffix() {
        #expect(TextEditDiff.edit(from: "Tiế", to: "Tiếng") == .init(deleteCount: 0, insert: "ng"))
    }

    @Test func telexReplacementDeletesThenInserts() {
        #expect(TextEditDiff.edit(from: "a", to: "â") == .init(deleteCount: 1, insert: "â"))
        #expect(TextEditDiff.edit(from: "Tie", to: "Tiê") == .init(deleteCount: 1, insert: "ê"))
    }

    @Test func backspaceDeletesOneCharacter() {
        #expect(TextEditDiff.edit(from: "việt", to: "việ") == .init(deleteCount: 1, insert: ""))
    }

    @Test func unchangedTextIsEmptyEdit() {
        #expect(TextEditDiff.edit(from: "xin chào", to: "xin chào").isEmpty)
    }

    @Test func composedAndDecomposedFormsAreEqual() {
        #expect(TextEditDiff.edit(from: "e\u{0302}", to: "ê").isEmpty)
    }

    @Test func emojiCountsAsOneCharacter() {
        #expect(TextEditDiff.edit(from: "a👨‍👩‍👧", to: "a") == .init(deleteCount: 1, insert: ""))
    }
}
