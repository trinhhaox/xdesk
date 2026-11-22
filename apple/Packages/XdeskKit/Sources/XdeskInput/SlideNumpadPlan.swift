import CoreGraphics

/// Mọi nút của chế độ "Slide & Số". Phím số dùng mã HID bàn phím số thật (Keypad 0x54–0x67).
public enum SlideNumpadControl: Hashable, Sendable {
    case start, end, previousSlide, nextSlide, space, undo
    case mediaPrevious, playPause, mediaNext, mute, volumeDown, volumeUp
    case key(usage: UInt16, label: String)

    /// Bàn phím số 4 cột × 4 hàng, hàng cuối là ⌫ và ↩ (Keypad Enter), mỗi nút rộng 2 cột.
    public static let keypadRows: [[SlideNumpadControl]] = [
        [.key(usage: 0x5F, label: "7"), .key(usage: 0x60, label: "8"), .key(usage: 0x61, label: "9"), .key(usage: 0x54, label: "/")],
        [.key(usage: 0x5C, label: "4"), .key(usage: 0x5D, label: "5"), .key(usage: 0x5E, label: "6"), .key(usage: 0x55, label: "*")],
        [.key(usage: 0x59, label: "1"), .key(usage: 0x5A, label: "2"), .key(usage: 0x5B, label: "3"), .key(usage: 0x56, label: "-")],
        [.key(usage: 0x62, label: "0"), .key(usage: 0x63, label: "."), .key(usage: 0x67, label: "="), .key(usage: 0x57, label: "+")],
    ]
    public static let backspace = SlideNumpadControl.key(usage: 0x2A, label: "⌫")
    public static let keypadEnter = SlideNumpadControl.key(usage: 0x58, label: "↩")
}

public struct SlideNumpadItem: Sendable, Equatable {
    public let control: SlideNumpadControl
    public let frame: CGRect
}

/// Bố cục Slide & Số từ kích thước vùng nội dung thật: dọc xếp chồng, ngang 3 cột; không cuộn, không chồng nhau.
public struct SlideNumpadPlan: Sendable {
    public static let spacing: CGFloat = 8
    public static let margin: CGFloat = 12
    public static let sectionGap: CGFloat = 12

    public let items: [SlideNumpadItem]
    public let isLandscape: Bool

    public init(size: CGSize) {
        isLandscape = size.width > size.height
        items = isLandscape ? Self.landscape(size) : Self.portrait(size)
    }

    // MARK: Dọc

    private static func portrait(_ size: CGSize) -> [SlideNumpadItem] {
        let area = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)
        var items: [SlideNumpadItem] = []
        var y = area.minY
        // Trình chiếu: ◀ ▶ lớn cạnh nhau, rồi 4 nút phụ một hàng.
        let bigHeight = min(72, area.height * 0.13)
        items += row([.previousSlide, .nextSlide], in: CGRect(x: area.minX, y: y, width: area.width, height: bigHeight))
        y += bigHeight + spacing
        let auxHeight = min(44, area.height * 0.08)
        items += row([.start, .end, .space, .undo], in: CGRect(x: area.minX, y: y, width: area.width, height: auxHeight))
        y += auxHeight + sectionGap
        let mediaHeight = min(48, area.height * 0.08)
        items += row(media, in: CGRect(x: area.minX, y: y, width: area.width, height: mediaHeight))
        y += mediaHeight + sectionGap
        // Bàn phím số: phần còn lại, ô vuông tối đa, canh giữa.
        items += keypad(in: CGRect(x: area.minX, y: y, width: area.width, height: area.maxY - y), squareCells: true)
        return items
    }

    // MARK: Ngang

    private static func landscape(_ size: CGSize) -> [SlideNumpadItem] {
        let area = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
        let usable = area.width - 2 * sectionGap
        let leftW = usable * 0.35
        let midW = usable * 0.20
        let rightW = usable - leftW - midW
        let left = CGRect(x: area.minX, y: area.minY, width: leftW, height: area.height)
        let mid = CGRect(x: left.maxX + sectionGap, y: area.minY, width: midW, height: area.height)
        let right = CGRect(x: mid.maxX + sectionGap, y: area.minY, width: rightW, height: area.height)

        var items: [SlideNumpadItem] = []
        let bigHeight = (left.height - 2 * spacing) * 0.5
        items += row([.previousSlide, .nextSlide], in: CGRect(x: left.minX, y: left.minY, width: left.width, height: bigHeight))
        let auxTop = left.minY + bigHeight + spacing
        items += grid([.start, .end, .space, .undo], columns: 2,
                      in: CGRect(x: left.minX, y: auxTop, width: left.width, height: left.maxY - auxTop))
        items += grid(media, columns: 2, in: mid)
        items += keypad(in: right, squareCells: false)
        return items
    }

    // MARK: Khối dựng chung

    private static let media: [SlideNumpadControl] = [.mediaPrevious, .playPause, .mediaNext, .mute, .volumeDown, .volumeUp]

    private static func row(_ controls: [SlideNumpadControl], in rect: CGRect) -> [SlideNumpadItem] {
        grid(controls, columns: controls.count, in: rect)
    }

    private static func grid(_ controls: [SlideNumpadControl], columns: Int, in rect: CGRect) -> [SlideNumpadItem] {
        let rows = (controls.count + columns - 1) / columns
        let cellW = (rect.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let cellH = (rect.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
        return controls.enumerated().map { index, control in
            let frame = CGRect(x: rect.minX + CGFloat(index % columns) * (cellW + spacing),
                               y: rect.minY + CGFloat(index / columns) * (cellH + spacing),
                               width: cellW, height: cellH)
            return SlideNumpadItem(control: control, frame: frame)
        }
    }

    /// 5 hàng: 4 hàng số 4 cột + hàng ⌫ ↩ (mỗi nút 2 cột).
    private static func keypad(in rect: CGRect, squareCells: Bool) -> [SlideNumpadItem] {
        let rows = CGFloat(keypadRowCount)
        let cellW = (rect.width - 3 * spacing) / 4
        var cellH = (rect.height - (rows - 1) * spacing) / rows
        if squareCells { cellH = min(cellH, cellW) }
        let totalH = rows * cellH + (rows - 1) * spacing
        let top = rect.minY + (rect.height - totalH) / 2
        func cell(column: Int, row: Int, span: Int = 1) -> CGRect {
            CGRect(x: rect.minX + CGFloat(column) * (cellW + spacing), y: top + CGFloat(row) * (cellH + spacing),
                   width: cellW * CGFloat(span) + spacing * CGFloat(span - 1), height: cellH)
        }
        var items: [SlideNumpadItem] = []
        for (r, controls) in SlideNumpadControl.keypadRows.enumerated() {
            for (c, control) in controls.enumerated() { items.append(SlideNumpadItem(control: control, frame: cell(column: c, row: r))) }
        }
        items.append(SlideNumpadItem(control: .backspace, frame: cell(column: 0, row: 4, span: 2)))
        items.append(SlideNumpadItem(control: .keypadEnter, frame: cell(column: 2, row: 4, span: 2)))
        return items
    }

    private static var keypadRowCount: Int { SlideNumpadControl.keypadRows.count + 1 }
}
