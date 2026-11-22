import XdeskWire

/// Một phím trên bàn phím Mac ANSI: nhãn US English, nhãn khi giữ Shift, HID usage (vị trí vật lý) và độ rộng
/// theo đơn vị phím (1.0 = một phím chữ). Hàng chuẩn rộng đúng 15 đơn vị.
public struct MacKey: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable { case letter, symbol, function, modifier, capsLock, action, fnLayer }

    public let usage: UInt16
    public let label: String
    public let shiftedLabel: String?
    public let width: Double
    public let kind: Kind
    public let modifier: InputModifiers?
    /// Nửa chiều cao (↑ ↓ xếp chồng trong cụm mũi tên).
    public let isHalfHeight: Bool

    public var id: UInt16 { usage }

    public init(usage: UInt16, label: String, shiftedLabel: String? = nil, width: Double = 1,
                kind: Kind, modifier: InputModifiers? = nil, isHalfHeight: Bool = false) {
        self.usage = usage
        self.label = label
        self.shiftedLabel = shiftedLabel
        self.width = width
        self.kind = kind
        self.modifier = modifier
        self.isHalfHeight = isHalfHeight
    }

    /// Nhãn hiển thị: chữ cái viết hoa khi Shift XOR Caps Lock; ký tự trên số/dấu chỉ đổi theo Shift.
    public func displayLabel(shift: Bool, capsLock: Bool) -> String {
        switch kind {
        case .letter: (shift != capsLock) ? label.uppercased() : label
        default: shift ? (shiftedLabel ?? label) : label
        }
    }
}

/// Bảng bố cục duy nhất cho bàn phím Mac (dùng chung iOS, Android bản sao dữ liệu này, viewer Mac sau này).
public enum MacKeyboardLayout {
    public static let rowUnits: Double = 15
    /// Hệ số chiều cao từng hàng so với hàng phím chuẩn (hàng F thấp hơn).
    public static let rowHeightScales: [Double] = [0.7, 1, 1, 1, 1, 1]

    public static let rows: [[MacKey]] = [functionRow, numberRow, topRow, homeRow, bottomRow, spaceRow]
    public static let allKeys: [MacKey] = rows.flatMap { $0 }

    /// Mã giả (không phải HID) của phím `fn` trên bố cục gọn: chỉ bật/tắt lớp F1–F12, không gửi sang Mac.
    public static let fnLayerUsage: UInt16 = 0x0100

    /// Bố cục gọn (không hàng F, 5 hàng): `fn` ở đầu hàng dưới; khi `fnLayer` bật, hàng số đổi thành esc F1–F12 ⌫.
    public static func compactRows(fnLayer: Bool) -> [[MacKey]] {
        [fnLayer ? fnNumberRow : numberRow, topRow, homeRow, bottomRow, compactSpaceRow]
    }

    private static func sym(_ usage: UInt16, _ label: String, _ shifted: String, width: Double = 1) -> MacKey {
        MacKey(usage: usage, label: label, shiftedLabel: shifted, width: width, kind: .symbol)
    }

    private static func letters(_ pairs: [(UInt16, String)]) -> [MacKey] {
        pairs.map { MacKey(usage: $0.0, label: $0.1, kind: .letter) }
    }

    private static func action(_ usage: UInt16, _ label: String, _ width: Double, kind: MacKey.Kind = .action) -> MacKey {
        MacKey(usage: usage, label: label, width: width, kind: kind)
    }

    private static func mod(_ usage: UInt16, _ label: String, _ width: Double, _ modifier: InputModifiers) -> MacKey {
        MacKey(usage: usage, label: label, width: width, kind: .modifier, modifier: modifier)
    }

    private static let functionRow: [MacKey] =
        [MacKey(usage: 0x29, label: "esc", width: 1.5, kind: .function)]
        + (0..<12).map { MacKey(usage: 0x3A + UInt16($0), label: "F\($0 + 1)", width: 1.125, kind: .function) }

    private static let numberRow: [MacKey] = [
        sym(0x35, "`", "~"), sym(0x1E, "1", "!"), sym(0x1F, "2", "@"), sym(0x20, "3", "#"), sym(0x21, "4", "$"),
        sym(0x22, "5", "%"), sym(0x23, "6", "^"), sym(0x24, "7", "&"), sym(0x25, "8", "*"), sym(0x26, "9", "("),
        sym(0x27, "0", ")"), sym(0x2D, "-", "_"), sym(0x2E, "=", "+"), action(0x2A, "delete ⌫", 2),
    ]

    private static let topRow: [MacKey] = [action(0x2B, "tab", 1.5)]
        + letters([(0x14, "q"), (0x1A, "w"), (0x08, "e"), (0x15, "r"), (0x17, "t"),
                   (0x1C, "y"), (0x18, "u"), (0x0C, "i"), (0x12, "o"), (0x13, "p")])
        + [sym(0x2F, "[", "{"), sym(0x30, "]", "}"), sym(0x31, "\\", "|", width: 1.5)]

    private static let homeRow: [MacKey] = [action(0x39, "caps lock", 1.75, kind: .capsLock)]
        + letters([(0x04, "a"), (0x16, "s"), (0x07, "d"), (0x09, "f"), (0x0A, "g"),
                   (0x0B, "h"), (0x0D, "j"), (0x0E, "k"), (0x0F, "l")])
        + [sym(0x33, ";", ":"), sym(0x34, "'", "\""), action(0x28, "return", 2.25)]

    private static let bottomRow: [MacKey] = [mod(0xE1, "shift", 2.25, .shift)]
        + letters([(0x1D, "z"), (0x1B, "x"), (0x06, "c"), (0x19, "v"), (0x05, "b"), (0x11, "n"), (0x10, "m")])
        + [sym(0x36, ",", "<"), sym(0x37, ".", ">"), sym(0x38, "/", "?"), mod(0xE5, "shift", 2.75, .shift)]

    private static let spaceRow: [MacKey] = [
        mod(0xE0, "⌃\ncontrol", 1.25, .control), mod(0xE2, "⌥\noption", 1.25, .option),
        mod(0xE3, "⌘\ncommand", 1.5, .command), action(0x2C, "", 5.25),
        mod(0xE7, "⌘\ncommand", 1.5, .command), mod(0xE6, "⌥\noption", 1.25, .option),
        action(0x50, "←", 1), MacKey(usage: 0x52, label: "↑", kind: .action, isHalfHeight: true),
        MacKey(usage: 0x51, label: "↓", kind: .action, isHalfHeight: true), action(0x4F, "→", 1),
    ]

    private static let fnNumberRow: [MacKey] =
        [MacKey(usage: 0x29, label: "esc", kind: .function)]
        + (0..<12).map { MacKey(usage: 0x3A + UInt16($0), label: "F\($0 + 1)", kind: .function) }
        + [action(0x2A, "delete ⌫", 2)]

    private static let compactSpaceRow: [MacKey] = [
        MacKey(usage: fnLayerUsage, label: "fn", kind: .fnLayer),
        mod(0xE0, "⌃\ncontrol", 1.25, .control), mod(0xE2, "⌥\noption", 1.25, .option),
        mod(0xE3, "⌘\ncommand", 1.5, .command), action(0x2C, "", 4.25),
        mod(0xE7, "⌘\ncommand", 1.5, .command), mod(0xE6, "⌥\noption", 1.25, .option),
        action(0x50, "←", 1), MacKey(usage: 0x52, label: "↑", kind: .action, isHalfHeight: true),
        MacKey(usage: 0x51, label: "↓", kind: .action, isHalfHeight: true), action(0x4F, "→", 1),
    ]
}
