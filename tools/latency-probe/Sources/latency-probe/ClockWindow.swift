import AppKit

/// Quy ước mã (khớp `LatencyOverlayView` trong app): ô vuông `cell` px, từ trái sang phải:
/// vạch đánh dấu 2 ô, 1 ô trống, 32 ô bit (MSB trước) của `UInt32(epoch ms)`. Trắng = 1, đen = 0.
enum ProbeCode {
    static let bitCount = 32
    static let sourceCell: CGFloat = 32
}

/// Cửa sổ không viền phủ màn hình ảo: nền đen, vạch tím + mã bit + số ms lớn, vẽ lại mỗi nhịp màn hình.
final class ClockWindow: NSWindow {
    @MainActor
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .statusBar
        backgroundColor = .black
        isReleasedWhenClosed = false
        let view = ClockView(frame: NSRect(origin: .zero, size: screen.frame.size))
        contentView = view
        view.startTicking()
    }
}

final class ClockView: NSView {
    private var link: CADisplayLink?
    private var nowMs: Int64 = 0

    @MainActor
    func startTicking() {
        link = displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }

    @MainActor @objc private func tick() {
        nowMs = Int64((Date().timeIntervalSince1970 * 1000).rounded())
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let cell = ProbeCode.sourceCell
        let top = bounds.height - cell * 2
        NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1).setFill()
        NSRect(x: cell, y: top, width: cell * 2, height: cell).fill()
        let code = UInt32(truncatingIfNeeded: nowMs)
        for bit in 0..<ProbeCode.bitCount {
            let on = (code >> UInt32(ProbeCode.bitCount - 1 - bit)) & 1 == 1
            (on ? NSColor.white : NSColor.black).setFill()
            NSRect(x: cell * CGFloat(bit + 4), y: top, width: cell, height: cell).fill()
        }
        let text = "\(nowMs)" as NSString
        text.draw(at: NSPoint(x: cell, y: top - 160), withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 120, weight: .bold), .foregroundColor: NSColor.white,
        ])
    }
}
