import UIKit
import XdeskInput
import XdeskWire

/// Bàn phím vật lý nối iPad: `UIPress.key.keyCode.rawValue` đã là HID usage nên gửi thẳng; giữ phím thì tự lặp phía viewer.
@MainActor
final class HardwareKeyboardHandler {
    private static let tickInterval: TimeInterval = 0.05

    private let send: ([InputEvent]) -> Void
    private var repeater = KeyRepeater()
    private var heldUsages: [UInt16: InputModifiers] = [:]
    private var timer: Timer?

    init(send: @escaping ([InputEvent]) -> Void) { self.send = send }

    /// `true` nếu mọi press là phím (đã xử lý); còn lại để UIKit xử lý tiếp.
    func pressesBegan(_ presses: Set<UIPress>) -> Bool {
        let keys = presses.compactMap(\.key)
        for key in keys {
            guard let usage = UInt16(exactly: key.keyCode.rawValue), usage != 0 else { continue }
            let mods = Self.modifiers(key.modifierFlags)
            heldUsages[usage] = mods
            send([.key(usage: usage, down: true, mods: mods)])
            repeater.keyDown(usage: usage, mods: mods, nowMs: Self.nowMs)
        }
        startTimerIfNeeded()
        return keys.count == presses.count
    }

    func pressesEnded(_ presses: Set<UIPress>) -> Bool {
        let keys = presses.compactMap(\.key)
        for key in keys {
            guard let usage = UInt16(exactly: key.keyCode.rawValue), heldUsages.removeValue(forKey: usage) != nil else { continue }
            repeater.keyUp(usage: usage)
            send([.key(usage: usage, down: false, mods: Self.modifiers(key.modifierFlags))])
        }
        return keys.count == presses.count
    }

    /// Mất focus / cửa sổ biến mất: nhả hết phím để host không bị kẹt.
    func releaseAll() {
        repeater.releaseAll()
        timer?.invalidate()
        timer = nil
        let ups = heldUsages.keys.map { InputEvent.key(usage: $0, down: false) }
        heldUsages.removeAll()
        if !ups.isEmpty { send(ups) }
    }

    private func startTimerIfNeeded() {
        guard repeater.isRepeating, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let events = repeater.tick(nowMs: Self.nowMs)
        if !events.isEmpty { send(events) }
        if !repeater.isRepeating {
            timer?.invalidate()
            timer = nil
        }
    }

    private static var nowMs: Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }

    private static func modifiers(_ flags: UIKeyModifierFlags) -> InputModifiers {
        var mods: InputModifiers = []
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.alternate) { mods.insert(.option) }
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.alphaShift) { mods.insert(.capsLock) }
        return mods
    }
}
