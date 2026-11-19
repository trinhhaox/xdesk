import Foundation

/// Tổ hợp phím từ danh sách tên (["cmd","shift","s"]): đúng một phím thường + các phím bổ trợ. Mã phím là virtual keycode ANSI.
public struct KeyChord: Sendable, Equatable {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1), shift = Modifiers(rawValue: 2), option = Modifiers(rawValue: 4)
        public static let control = Modifiers(rawValue: 8), function = Modifiers(rawValue: 16)
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    private static let modifierNames: [String: Modifiers] = [
        "cmd": .command, "command": .command, "meta": .command, "shift": .shift, "alt": .option, "option": .option, "opt": .option,
        "ctrl": .control, "control": .control, "fn": .function,
    ]

    private static let keyCodes: [String: UInt16] = {
        var table: [String: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
            "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
            "n": 45, "m": 46, ".": 47, "`": 50,
            "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
            "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
            "left": 123, "right": 124, "down": 125, "up": 126,
        ]
        let function: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (index, code) in function.enumerated() { table["f\(index + 1)"] = code }
        return table
    }()

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case empty, noKey, manyKeys, unknown(String)

        public var description: String {
            switch self {
            case .empty: "keys rỗng"
            case .noKey: "thiếu phím thường (chỉ có phím bổ trợ)"
            case .manyKeys: "chỉ được một phím thường trong tổ hợp"
            case .unknown(let name): "không biết phím: \(name)"
            }
        }
    }

    public static func parse(_ names: [String]) throws -> KeyChord {
        guard !names.isEmpty else { throw ParseError.empty }
        var modifiers: Modifiers = []
        var key: UInt16?
        for raw in names {
            let name = raw.lowercased()
            if let modifier = modifierNames[name] { modifiers.insert(modifier); continue }
            guard let code = keyCodes[name] else { throw ParseError.unknown(raw) }
            guard key == nil else { throw ParseError.manyKeys }
            key = code
        }
        guard let key else { throw ParseError.noKey }
        return KeyChord(keyCode: key, modifiers: modifiers)
    }
}
