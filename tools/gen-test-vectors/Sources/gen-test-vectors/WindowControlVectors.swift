import XdeskWire

/// Chỉnh cửa sổ Mac từ điện thoại (cap `windowControl`, bit 14).
let windowControlMessages: [(String, UInt32, ControlMessage)] = [
    ("window-pick", 60, .windowPick(WindowPick(x: 412.5, y: 300))),
    ("window-selected-ok", 61, .windowSelected(WindowSelected(
        ok: true, windowId: 1042, app: "Safari", title: "Trang chủ", frame: WindowFrame(x: 100, y: 80.5, w: 640, h: 480), resizable: true))),
    ("window-selected-not-resizable", 62, .windowSelected(WindowSelected(
        ok: true, windowId: 7, app: "Máy tính", frame: WindowFrame(x: 20, y: 20, w: 230, h: 340), resizable: false))),
    ("window-selected-failure", 63, .windowSelected(.failure("Không có cửa sổ ở đây"))),
    ("window-adjust-move", 64, .windowAdjust(.move(windowId: 1042, dx: -12.5, dy: 30))),
    ("window-adjust-resize", 65, .windowAdjust(.resize(windowId: 1042, w: 800, h: 600.5))),
    ("window-adjust-preset-fill", 66, .windowAdjust(.preset(windowId: 1042, .fill))),
    ("window-adjust-preset-left", 66, .windowAdjust(.preset(windowId: 1042, .left))),
    ("window-adjust-preset-right", 66, .windowAdjust(.preset(windowId: 1042, .right))),
    ("window-adjust-preset-center", 66, .windowAdjust(.preset(windowId: 1042, .center))),
    ("window-adjust-preset-restore", 66, .windowAdjust(.preset(windowId: 1042, .restore))),
]

let windowControlInvalidMessages: [(String, String, String)] = [
    ("window-pick-missing-y", "{\"id\":1,\"t\":\"window.pick\",\"x\":1}", "malformedJSON"),
    ("window-selected-missing-ok", "{\"id\":1,\"t\":\"window.selected\"}", "malformedJSON"),
    ("window-selected-zero-width-frame", "{\"frame\":{\"h\":10,\"w\":0,\"x\":0,\"y\":0},\"id\":1,\"ok\":true,\"t\":\"window.selected\",\"windowId\":1}", "invalidField"),
    ("window-adjust-unknown-op", "{\"id\":1,\"op\":\"rotate\",\"t\":\"window.adjust\",\"windowId\":1}", "malformedJSON"),
    ("window-adjust-unknown-preset", "{\"id\":1,\"op\":\"preset\",\"preset\":\"top\",\"t\":\"window.adjust\",\"windowId\":1}", "malformedJSON"),
    ("window-adjust-missing-window-id", "{\"dx\":1,\"dy\":1,\"id\":1,\"op\":\"move\",\"t\":\"window.adjust\"}", "malformedJSON"),
    ("window-adjust-move-missing-dy", "{\"dx\":1,\"id\":1,\"op\":\"move\",\"t\":\"window.adjust\",\"windowId\":1}", "invalidField"),
    ("window-adjust-resize-zero-height", "{\"h\":0,\"id\":1,\"op\":\"resize\",\"t\":\"window.adjust\",\"w\":300,\"windowId\":1}", "invalidField"),
    ("window-adjust-resize-negative-width", "{\"h\":300,\"id\":1,\"op\":\"resize\",\"t\":\"window.adjust\",\"w\":-5,\"windowId\":1}", "invalidField"),
    ("window-adjust-preset-missing-preset", "{\"id\":1,\"op\":\"preset\",\"t\":\"window.adjust\",\"windowId\":1}", "invalidField"),
]
