import CoreGraphics
import Foundation
@testable import Xdesk

/// Ghi lại các lệnh tiêm thay vì gọi CGEvent.
final class FakeEventInjector: EventInjecting, @unchecked Sendable {
    enum Call: Equatable {
        case move(CGPoint, held: MouseButton?)
        case button(MouseButton, down: Bool, CGPoint, clicks: Int)
        case scroll(Int32, Int32)
        case key(CGKeyCode, down: Bool, flags: CGEventFlags)
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    var calls: [Call] { lock.withLock { recorded } }
    private func record(_ call: Call) { lock.withLock { recorded.append(call) } }

    func mouseMove(to point: CGPoint, held: MouseButton?, flags: CGEventFlags) { record(.move(point, held: held)) }
    func mouseButton(_ button: MouseButton, down: Bool, at point: CGPoint, clickCount: Int, flags: CGEventFlags) {
        record(.button(button, down: down, point, clicks: clickCount))
    }
    func scroll(dx: Int32, dy: Int32, flags: CGEventFlags) { record(.scroll(dx, dy)) }
    func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) { record(.key(code, down: down, flags: flags)) }
}
