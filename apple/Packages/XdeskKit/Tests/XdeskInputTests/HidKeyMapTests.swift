import Testing
@testable import XdeskInput

@Suite struct HidKeyMapTests {
    @Test func lettersFollowAnsiLayout() {
        let expected: [(Character, UInt16)] = [("A", 0), ("S", 1), ("Z", 6), ("Q", 12), ("M", 46), ("P", 35), ("B", 11)]
        for (letter, code) in expected {
            let usage = 0x04 + UInt16(letter.asciiValue ?? 0) - 65
            #expect(HidKeyMap.macKeyCode(forHidUsage: usage) == code, "\(letter)")
        }
    }

    @Test func digitsAndFunctionKeys() {
        #expect(HidKeyMap.macKeyCode(forHidUsage: 0x1E) == 18) // 1
        #expect(HidKeyMap.macKeyCode(forHidUsage: 0x27) == 29) // 0
        #expect(HidKeyMap.macKeyCode(forHidUsage: 0x22) == 23) // 5
        #expect(HidKeyMap.macKeyCode(forHidUsage: 0x3A) == 122) // F1
        #expect(HidKeyMap.macKeyCode(forHidUsage: 0x45) == 111) // F12
        #expect(HidKeyMap.macKeyCode(forHidUsage: 0x3E) == 96) // F5
    }

    @Test func controlAndNavigationKeys() {
        let table: [UInt16: UInt16] = [
            0x28: 36, 0x2B: 48, 0x2C: 49, 0x2A: 51, 0x29: 53, 0x4C: 117,
            0x4F: 124, 0x50: 123, 0x51: 125, 0x52: 126, 0x4A: 115, 0x4D: 119, 0x4B: 116, 0x4E: 121,
        ]
        for (usage, code) in table { #expect(HidKeyMap.macKeyCode(forHidUsage: usage) == code, "usage \(usage)") }
    }

    @Test func punctuation() {
        let table: [UInt16: UInt16] = [0x2D: 27, 0x2E: 24, 0x2F: 33, 0x30: 30, 0x31: 42, 0x33: 41, 0x34: 39, 0x35: 50, 0x36: 43, 0x37: 47, 0x38: 44]
        for (usage, code) in table { #expect(HidKeyMap.macKeyCode(forHidUsage: usage) == code, "usage \(usage)") }
    }

    @Test func leftAndRightModifiersAreDistinct() {
        let table: [UInt16: UInt16] = [0xE0: 59, 0xE1: 56, 0xE2: 58, 0xE3: 55, 0xE4: 62, 0xE5: 60, 0xE6: 61, 0xE7: 54]
        for (usage, code) in table { #expect(HidKeyMap.macKeyCode(forHidUsage: usage) == code, "usage \(usage)") }
    }

    @Test func unknownUsageIsNil() {
        #expect(HidKeyMap.macKeyCode(forHidUsage: 0) == nil)
        #expect(HidKeyMap.macKeyCode(forHidUsage: 0x46) == nil)
        #expect(HidKeyMap.macKeyCode(forHidUsage: 0xFFFF) == nil)
    }

    @Test func mainBlockHasNoDuplicateKeyCodes() {
        let usages = Array(0x04...0x38).filter { $0 != 0x32 } + Array(0x3A...0x45) + [0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7]
        let codes = usages.compactMap { HidKeyMap.macKeyCode(forHidUsage: UInt16($0)) }
        #expect(codes.count == Set(codes).count)
    }

    @Test func reverseMapRoundTrips() {
        for usage in UInt16(0x04)...0x38 {
            guard let code = HidKeyMap.macKeyCode(forHidUsage: usage), usage != 0x32 else { continue }
            #expect(HidKeyMap.hidUsage(forMacKeyCode: code) == usage)
        }
        #expect(HidKeyMap.hidUsage(forMacKeyCode: 42) == 0x31)
        #expect(HidKeyMap.hidUsage(forMacKeyCode: 9999) == nil)
    }
}
