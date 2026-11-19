import AppKit
import ApplicationServices
import XdeskAgent

/// Duyệt cây AX của các app có cửa sổ trên màn hình agent. Giới hạn độ sâu, số phần tử và 500 ms để không treo với Electron/canvas.
struct AxTreeReader: Sendable {
    static let maxDepth = 10
    static let maxElements = 300
    static let timeBudget: Duration = .milliseconds(500)
    private static let interesting: Set<String> = [
        "AXWindow", "AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXMenuItem", "AXMenuBarItem", "AXLink", "AXSlider", "AXComboBox", "AXTabGroup", "AXStaticText", "AXSearchField", "AXToolbar",
    ]

    struct Result: Sendable {
        var elements: [UiElement]
        var truncated: Bool
    }

    /// `origin` = góc trên-trái màn hình agent (toạ độ toàn cục); frame trả về tương đối với góc đó.
    func read(in bounds: CGRect) -> Result {
        let deadline = ContinuousClock.now + Self.timeBudget
        var elements: [UiElement] = []
        var truncated = false
        let own = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != own {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.15)
            for window in AxAttributes.elements(root, kAXWindowsAttribute) {
                guard let frame = AxAttributes.frame(window), frame.intersects(bounds) else { continue }
                visit(window, depth: 0, bounds: bounds, deadline: deadline, into: &elements, truncated: &truncated)
            }
            if truncated { break }
        }
        return Result(elements: elements, truncated: truncated)
    }

    private func visit(_ element: AXUIElement, depth: Int, bounds: CGRect, deadline: ContinuousClock.Instant, into out: inout [UiElement], truncated: inout Bool) {
        guard !truncated else { return }
        if out.count >= Self.maxElements || ContinuousClock.now > deadline || depth > Self.maxDepth { truncated = true; return }
        let role = AxAttributes.string(element, kAXRoleAttribute) ?? ""
        if Self.interesting.contains(role), let frame = AxAttributes.frame(element), frame.width > 0, frame.height > 0, frame.intersects(bounds) {
            let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXPlaceholderValueAttribute]
                .lazy.compactMap { AxAttributes.string(element, $0) }.first { !$0.isEmpty } ?? ""
            out.append(UiElement(ref: "e\(out.count + 1)", role: role, label: String(label.prefix(80)),
                                 x: frame.minX - bounds.minX, y: frame.minY - bounds.minY, width: frame.width, height: frame.height))
        }
        for child in AxAttributes.elements(element, kAXChildrenAttribute) {
            visit(child, depth: depth + 1, bounds: bounds, deadline: deadline, into: &out, truncated: &truncated)
        }
    }
}
