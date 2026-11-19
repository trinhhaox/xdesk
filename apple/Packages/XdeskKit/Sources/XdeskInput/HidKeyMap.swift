/// USB HID usage (Keyboard/Keypad page 0x07, vị trí phím) ↔ `CGKeyCode` macOS (kVK_ANSI_*, bố cục vật lý ANSI).
public enum HidKeyMap {
    private static let letters: [UInt16] = [0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6]
    private static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
    private static let functionKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
    private static let extraFunctionKeys: [UInt16] = [105, 107, 113, 106, 64, 79, 80, 90]
    private static let keypadDigits: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92, 82]

    private static let table: [UInt16: UInt16] = {
        var map: [UInt16: UInt16] = [:]
        for (i, code) in letters.enumerated() { map[0x04 + UInt16(i)] = code }
        for (i, code) in digits.enumerated() { map[0x1E + UInt16(i)] = code }
        for (i, code) in functionKeys.enumerated() { map[0x3A + UInt16(i)] = code }
        for (i, code) in extraFunctionKeys.enumerated() { map[0x68 + UInt16(i)] = code }
        for (i, code) in keypadDigits.enumerated() { map[0x59 + UInt16(i)] = code }
        let fixed: [UInt16: UInt16] = [
            0x28: 36, 0x29: 53, 0x2A: 51, 0x2B: 48, 0x2C: 49, 0x2D: 27, 0x2E: 24, 0x2F: 33, 0x30: 30,
            0x31: 42, 0x32: 42, 0x33: 41, 0x34: 39, 0x35: 50, 0x36: 43, 0x37: 47, 0x38: 44, 0x39: 57,
            0x49: 114, 0x4A: 115, 0x4B: 116, 0x4C: 117, 0x4D: 119, 0x4E: 121,
            0x4F: 124, 0x50: 123, 0x51: 125, 0x52: 126,
            0x53: 71, 0x54: 75, 0x55: 67, 0x56: 78, 0x57: 69, 0x58: 76, 0x63: 65, 0x64: 10, 0x67: 81,
            0xE0: 59, 0xE1: 56, 0xE2: 58, 0xE3: 55, 0xE4: 62, 0xE5: 60, 0xE6: 61, 0xE7: 54,
        ]
        map.merge(fixed) { _, new in new }
        return map
    }()

    /// Ưu tiên usage nhỏ nhất khi nhiều usage cùng ra một keycode (vd. `\` và non-US `#`).
    private static let reverse: [UInt16: UInt16] = {
        var map: [UInt16: UInt16] = [:]
        for usage in table.keys.sorted() {
            if let code = table[usage], map[code] == nil { map[code] = usage }
        }
        return map
    }()

    /// `CGKeyCode` cho HID usage; nil nếu phím chưa hỗ trợ (host bỏ qua).
    public static func macKeyCode(forHidUsage usage: UInt16) -> UInt16? { table[usage] }

    /// Chiều ngược lại cho viewer Mac (NSEvent.keyCode → HID usage).
    public static func hidUsage(forMacKeyCode code: UInt16) -> UInt16? { reverse[code] }

    /// HID usage của một ký tự gõ được bằng một phím ANSI không cần Shift (a–z, 0–9, dấu cách); nil nếu không có.
    /// Dùng khi có bổ trợ dính (⌘ + "c" → ⌘C) vì lúc đó chữ phải đi như phím, không phải văn bản.
    public static func hidUsage(forCharacter character: Character) -> UInt16? {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first, scalar.isASCII else { return nil }
        switch scalar.value {
        case 0x61...0x7A: return 0x04 + UInt16(scalar.value - 0x61)
        case 0x31...0x39: return 0x1E + UInt16(scalar.value - 0x31)
        case 0x30: return 0x27
        case 0x20: return 0x2C
        default: return nil
        }
    }
}
