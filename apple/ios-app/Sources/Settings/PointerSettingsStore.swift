import Foundation
import Observation
import XdeskInput

/// Cài đặt con trỏ lưu trong UserDefaults; đọc lại mỗi lần mở màn stream, đổi là lưu ngay.
@MainActor
@Observable
final class PointerSettingsStore {
    private enum Key {
        static let mode = "xdesk.pointer.mode"
        static let speed = "xdesk.pointer.speed"
        static let naturalScroll = "xdesk.pointer.naturalScroll"
        static let longPress = "xdesk.pointer.longPressRightClick"
        static let doubleTapKeyboard = "xdesk.pointer.doubleTapOpensKeyboard"
    }

    var settings: PointerSettings { didSet { save() } }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = PointerSettings()
        settings = PointerSettings(
            mode: defaults.string(forKey: Key.mode).flatMap(PointerMode.init(rawValue:)) ?? fallback.mode,
            speed: (defaults.object(forKey: Key.speed) as? Double).map(Float.init) ?? fallback.speed,
            naturalScroll: defaults.object(forKey: Key.naturalScroll) as? Bool ?? fallback.naturalScroll,
            longPressRightClick: defaults.object(forKey: Key.longPress) as? Bool ?? fallback.longPressRightClick,
            doubleTapOpensKeyboard: defaults.object(forKey: Key.doubleTapKeyboard) as? Bool ?? fallback.doubleTapOpensKeyboard
        )
    }

    func toggleMode() { settings.mode = settings.mode == .direct ? .trackpad : .direct }

    private func save() {
        defaults.set(settings.mode.rawValue, forKey: Key.mode)
        defaults.set(Double(settings.speed), forKey: Key.speed)
        defaults.set(settings.naturalScroll, forKey: Key.naturalScroll)
        defaults.set(settings.longPressRightClick, forKey: Key.longPress)
        defaults.set(settings.doubleTapOpensKeyboard, forKey: Key.doubleTapKeyboard)
    }
}

extension PointerMode {
    var title: String { self == .direct ? "Chạm trực tiếp" : "Con trỏ" }
    var symbol: String { self == .direct ? "hand.tap" : "cursorarrow.motionlines" }
}
