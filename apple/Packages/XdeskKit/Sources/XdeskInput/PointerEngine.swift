import XdeskWire

/// Chọn bộ diễn giải theo `PointerSettings.mode`: trực tiếp (`GestureInterpreter`) hay trackpad (`TrackpadInterpreter`).
/// Giữ nguyên vị trí con trỏ khi đổi cài đặt giữa chừng bằng cách dựng engine mới với `cursor` cũ.
public struct PointerEngine: Sendable {
    private enum Backend: Sendable {
        case direct(GestureInterpreter)
        case trackpad(TrackpadInterpreter)
    }

    private var backend: Backend

    public init(settings: PointerSettings, surfaceWidth: Float, surfaceHeight: Float, cursor: (x: Float, y: Float)? = nil) {
        switch settings.mode {
        case .direct:
            var config = GestureConfig(surfaceWidth: surfaceWidth, surfaceHeight: surfaceHeight)
            config.longPressRightClick = settings.longPressRightClick
            config.naturalScroll = settings.naturalScroll
            backend = .direct(GestureInterpreter(config: config))
        case .trackpad:
            var config = TrackpadConfig(surfaceWidth: surfaceWidth, surfaceHeight: surfaceHeight)
            config.speed = settings.speed
            config.longPressRightClick = settings.longPressRightClick
            config.naturalScroll = settings.naturalScroll
            backend = .trackpad(TrackpadInterpreter(config: config, cursor: cursor ?? (0.5, 0.5)))
        }
    }

    /// Vị trí con trỏ cục bộ; nil ở chế độ trực tiếp (không có con trỏ tương đối).
    public var cursor: (x: Float, y: Float)? {
        if case .trackpad(let trackpad) = backend { return trackpad.cursor }
        return nil
    }

    public mutating func handle(_ sample: TouchSample) -> [InputEvent] {
        switch backend {
        case .direct(var gesture):
            let events = gesture.handle(sample)
            backend = .direct(gesture)
            return events
        case .trackpad(var trackpad):
            let events = trackpad.handle(sample)
            backend = .trackpad(trackpad)
            return events
        }
    }

    public mutating func tick(nowMs: Int64) -> [InputEvent] {
        switch backend {
        case .direct(var gesture):
            let events = gesture.tick(nowMs: nowMs)
            backend = .direct(gesture)
            return events
        case .trackpad(var trackpad):
            let events = trackpad.tick(nowMs: nowMs)
            backend = .trackpad(trackpad)
            return events
        }
    }
}
