import AppKit

/// Lớp phủ đo độ trễ (tool `latency-probe`): vạch xanh lá + 32 ô bit của (giờ host ước lượng) tại mỗi nhịp màn hình.
/// Đặt cạnh hình probe của host (vạch tím + 32 ô bit) trong cùng một ảnh chụp → hiệu hai mã = độ trễ glass-to-glass.
/// Quy ước mã: xem `tools/latency-probe/README.md`.
@MainActor
final class LatencyOverlayView: NSView {
    static let bitCount = 32
    static let cell: CGFloat = 16
    private let session: ViewerSession
    private var link: CADisplayLink?
    private var code: UInt32 = 0

    init(session: ViewerSession) {
        self.session = session
        super.init(frame: .zero)
        link = displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit { link?.invalidate() }

    @objc private func tick() {
        guard let hostNow = session.hostNowMs() else { return }
        code = UInt32(truncatingIfNeeded: hostNow)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let cell = Self.cell
        NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: cell * 2, height: cell).fill()
        for bit in 0..<Self.bitCount {
            let on = (code >> UInt32(Self.bitCount - 1 - bit)) & 1 == 1
            (on ? NSColor.white : NSColor.black).setFill()
            NSRect(x: cell * CGFloat(bit + 3), y: 0, width: cell, height: cell).fill()
        }
    }
}
