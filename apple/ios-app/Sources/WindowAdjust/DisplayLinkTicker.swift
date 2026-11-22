import UIKit

/// `CADisplayLink` giữ target mạnh nên đi qua lớp này; tối đa 60 Hz (host nhận tối đa 60 lệnh/giây).
@MainActor
final class DisplayLinkTicker: NSObject {
    private var link: CADisplayLink?
    private let onTick: () -> Void

    init(onTick: @escaping () -> Void) {
        self.onTick = onTick
        super.init()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() { onTick() }

    func stop() {
        link?.invalidate()
        link = nil
    }
}
