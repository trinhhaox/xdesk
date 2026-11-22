import Testing
@testable import XdeskInput

@Suite struct MacKeyboardLayoutTests {
    private let keys = MacKeyboardLayout.allKeys

    @Test func sixRowsWithExpectedKeyCounts() {
        let counts = MacKeyboardLayout.rows.map(\.count)
        #expect(counts == [13, 14, 14, 13, 12, 10])
        #expect(MacKeyboardLayout.rowHeightScales.count == MacKeyboardLayout.rows.count)
    }

    @Test func everyKeyHasValidHidUsageAndMacKeyCode() {
        for key in keys {
            #expect((0x04...0xE7).contains(key.usage), "usage \(key.usage) for \(key.label)")
            #expect(HidKeyMap.macKeyCode(forHidUsage: key.usage) != nil, "no Mac keycode for \(key.label)")
        }
    }

    @Test func usagesAreUnique() {
        #expect(Set(keys.map(\.usage)).count == keys.count)
    }

    @Test func sidedModifiersUseDistinctUsagesButSharedBits() {
        let shifts = keys.filter { $0.modifier == .shift }
        let commands = keys.filter { $0.modifier == .command }
        let options = keys.filter { $0.modifier == .option }
        #expect(shifts.map(\.usage).sorted() == [0xE1, 0xE5])
        #expect(commands.map(\.usage).sorted() == [0xE3, 0xE7])
        #expect(options.map(\.usage).sorted() == [0xE2, 0xE6])
        #expect(keys.filter { $0.modifier == .control }.map(\.usage) == [0xE0])
    }

    @Test func rowsFillFifteenUnits() {
        for (index, row) in MacKeyboardLayout.rows.enumerated() {
            // ↑ ↓ xếp chồng nên chỉ tính một cột.
            let skipped = row.filter(\.isHalfHeight).dropFirst()
            let total = row.map(\.width).reduce(0, +) - skipped.map(\.width).reduce(0, +)
            #expect(abs(total - MacKeyboardLayout.rowUnits) < 0.0001, "row \(index) = \(total)")
        }
    }

    @Test func lettersFollowQwertyPositionsAndUppercaseWithShiftOrCaps() throws {
        let q = try #require(keys.first { $0.usage == 0x14 })
        #expect(q.displayLabel(shift: false, capsLock: false) == "q")
        #expect(q.displayLabel(shift: true, capsLock: false) == "Q")
        #expect(q.displayLabel(shift: false, capsLock: true) == "Q")
        #expect(q.displayLabel(shift: true, capsLock: true) == "q")
    }

    @Test func shiftedLabelsMatchUsAnsi() {
        let expected: [UInt16: String] = [
            0x35: "~", 0x1E: "!", 0x1F: "@", 0x20: "#", 0x21: "$", 0x22: "%", 0x23: "^", 0x24: "&", 0x25: "*",
            0x26: "(", 0x27: ")", 0x2D: "_", 0x2E: "+", 0x2F: "{", 0x30: "}", 0x31: "|", 0x33: ":", 0x34: "\"",
            0x36: "<", 0x37: ">", 0x38: "?",
        ]
        for (usage, shifted) in expected {
            let key = keys.first { $0.usage == usage }
            #expect(key?.displayLabel(shift: true, capsLock: false) == shifted)
            // Caps Lock không đổi ký tự trên phím số/dấu.
            #expect(key?.displayLabel(shift: false, capsLock: true) == key?.label)
        }
    }

    @Test func arrowClusterAndSpaceExist() {
        #expect(keys.first { $0.usage == 0x2C }?.width == 5.25)
        let arrows = keys.filter { [0x4F, 0x50, 0x51, 0x52].contains($0.usage) }
        #expect(arrows.count == 4)
        #expect(arrows.filter(\.isHalfHeight).map(\.usage).sorted() == [0x51, 0x52])
    }
}
