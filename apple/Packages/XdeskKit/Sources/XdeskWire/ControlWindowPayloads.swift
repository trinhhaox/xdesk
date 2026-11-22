/// Chỉnh cửa sổ Mac từ viewer (cap `windowControl`). Toạ độ theo hệ điểm của luồng video viewer đang xem.

public enum WindowAdjustOp: String, Codable, Sendable, CaseIterable { case move, resize, preset }

public enum WindowPreset: String, Codable, Sendable, CaseIterable { case fill, left, right, center, restore }

public struct WindowFrame: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }

    var isValid: Bool { x.isFinite && y.isFinite && w.isFinite && h.isFinite && w > 0 && h > 0 }
}

/// Viewer → host: chọn cửa sổ trên cùng tại điểm (x, y). Host trả `window.selected`.
public struct WindowPick: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }

    func validate() throws {
        guard x.isFinite, y.isFinite else { throw WireError.invalidField("window.pick.xy") }
    }
}

/// Host → viewer: kết quả chọn/chỉnh. `ok == false` kèm `message` tiếng Việt.
public struct WindowSelected: Codable, Sendable, Equatable {
    public static let maxTextBytes = 256

    public var ok: Bool
    public var windowId: UInt32?
    public var app: String?
    public var title: String?
    public var frame: WindowFrame?
    public var resizable: Bool?
    public var message: String?

    public init(
        ok: Bool, windowId: UInt32? = nil, app: String? = nil, title: String? = nil,
        frame: WindowFrame? = nil, resizable: Bool? = nil, message: String? = nil
    ) {
        self.ok = ok; self.windowId = windowId; self.app = app; self.title = title
        self.frame = frame; self.resizable = resizable; self.message = message
    }

    public static func failure(_ message: String) -> WindowSelected { WindowSelected(ok: false, message: message) }

    func validate() throws {
        if let frame, !frame.isValid { throw WireError.invalidField("window.selected.frame") }
        for text in [app, title, message] where (text?.utf8.count ?? 0) > Self.maxTextBytes {
            throw WireError.invalidField("window.selected.text")
        }
    }
}

/// Viewer → host: `move` cần `dx`,`dy`; `resize` cần `w`,`h` (> 0); `preset` cần `preset`.
public struct WindowAdjust: Codable, Sendable, Equatable {
    public var windowId: UInt32
    public var op: WindowAdjustOp
    public var dx: Double?
    public var dy: Double?
    public var w: Double?
    public var h: Double?
    public var preset: WindowPreset?

    public init(
        windowId: UInt32, op: WindowAdjustOp, dx: Double? = nil, dy: Double? = nil,
        w: Double? = nil, h: Double? = nil, preset: WindowPreset? = nil
    ) {
        self.windowId = windowId; self.op = op; self.dx = dx; self.dy = dy; self.w = w; self.h = h; self.preset = preset
    }

    public static func move(windowId: UInt32, dx: Double, dy: Double) -> WindowAdjust {
        WindowAdjust(windowId: windowId, op: .move, dx: dx, dy: dy)
    }
    public static func resize(windowId: UInt32, w: Double, h: Double) -> WindowAdjust {
        WindowAdjust(windowId: windowId, op: .resize, w: w, h: h)
    }
    public static func preset(windowId: UInt32, _ preset: WindowPreset) -> WindowAdjust {
        WindowAdjust(windowId: windowId, op: .preset, preset: preset)
    }

    func validate() throws {
        switch op {
        case .move:
            guard let dx, let dy, dx.isFinite, dy.isFinite else { throw WireError.invalidField("window.adjust.move") }
        case .resize:
            guard let w, let h, w.isFinite, h.isFinite, w > 0, h > 0 else { throw WireError.invalidField("window.adjust.resize") }
        case .preset:
            guard preset != nil else { throw WireError.invalidField("window.adjust.preset") }
        }
    }
}
