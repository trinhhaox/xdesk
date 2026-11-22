import CoreGraphics
import Testing
@testable import XdeskInput

/// Kích thước vùng nội dung (sau thanh trên 48 dọc / 36 ngang, trừ safe area) của 4 thiết bị mẫu.
private let contentSizes: [(name: String, size: CGSize)] = [
    ("932x430", CGSize(width: 932 - 94, height: 430 - 36 - 21)),
    ("430x932", CGSize(width: 430, height: 932 - 48 - 34)),
    ("667x375", CGSize(width: 667, height: 375 - 36)),
    ("375x667", CGSize(width: 375, height: 667 - 48 - 34)),
]

private func overlaps(_ rects: [(String, CGRect)]) -> [String] {
    var bad: [String] = []
    for i in rects.indices {
        for j in rects.indices where j > i && rects[i].1.intersects(rects[j].1) {
            bad.append("\(rects[i].0) x \(rects[j].0)")
        }
    }
    return bad
}

@Suite struct MacKeyboardGeometryTests {
    @Test func compactRowsFillFifteenUnitsWithUniqueUsages() {
        for fn in [false, true] {
            let rows = MacKeyboardLayout.compactRows(fnLayer: fn)
            #expect(rows.count == 5)
            for row in rows {
                let skipped = row.filter(\.isHalfHeight).dropFirst()
                let total = row.map(\.width).reduce(0, +) - skipped.map(\.width).reduce(0, +)
                #expect(abs(total - 15) < 0.0001)
            }
            let usages = rows.flatMap { $0 }.map(\.usage)
            #expect(Set(usages).count == usages.count)
            #expect(usages.contains(MacKeyboardLayout.fnLayerUsage))
        }
        let fnKeys = MacKeyboardLayout.compactRows(fnLayer: true)[0]
        #expect(fnKeys.map(\.label).prefix(3) == ["esc", "F1", "F2"])
    }

    @Test func keysNeverOverlapAndKeepMinimumHeight() {
        for (name, content) in contentSizes {
            let plan = KeyboardScreenPlan(size: content)
            for fn in [false, true] {
                let geometry = MacKeyboardGeometry(available: plan.keyboard.size, minKeyHeight: plan.minKeyHeight, fnLayerOn: fn)
                let rects = geometry.frames.map { (String($0.key), $0.value) }
                #expect(overlaps(rects).isEmpty, "\(name) fn=\(fn): \(overlaps(rects))")
                #expect(geometry.size.height <= plan.keyboard.height + 0.5, "\(name)")
                #expect(geometry.size.width <= plan.keyboard.width + 0.5, "\(name)")
                for (usage, frame) in geometry.frames where usage != 0x29 && !(0x3A...0x45).contains(usage) {
                    // ↑ ↓ xếp chồng chỉ cao nửa phím.
                    let halfHeight = usage == 0x51 || usage == 0x52
                    let expected = plan.minKeyHeight / (halfHeight ? 2 : 1) - (halfHeight ? MacKeyboardGeometry.gap : 0)
                    #expect(frame.height >= expected - 0.5, "\(name) usage \(usage) h=\(frame.height)")
                }
            }
        }
    }

    @Test func landscapeShortScreenHidesFunctionRowAndTallScreenShowsIt() {
        let short = KeyboardScreenPlan(size: CGSize(width: 667, height: 200))
        #expect(MacKeyboardGeometry(available: short.keyboard.size, minKeyHeight: short.minKeyHeight).isCompact)
        let tall = KeyboardScreenPlan(size: contentSizes[0].size)
        #expect(!MacKeyboardGeometry(available: tall.keyboard.size, minKeyHeight: tall.minKeyHeight).isCompact)
    }

    @Test func portraitSplitsPadAboveKeyboardWithoutOverlap() throws {
        for (name, content) in contentSizes where content.height > content.width {
            let plan = KeyboardScreenPlan(size: content)
            let pad = try #require(plan.pad)
            #expect(pad.height >= KeyboardScreenPlan.minPadHeight, "\(name)")
            #expect(pad.maxY <= plan.keyboard.minY + 0.001, "\(name)")
            #expect(plan.keyboard.maxY <= content.height + 0.001, "\(name)")
        }
        #expect(KeyboardScreenPlan(size: contentSizes[0].size).pad == nil)
    }
}

@Suite struct SlideNumpadPlanTests {
    @Test func noOverlapAndInsideBounds() {
        for (name, content) in contentSizes {
            let plan = SlideNumpadPlan(size: content)
            let rects = plan.items.enumerated().map { ("\($0.offset):\($0.element.control)", $0.element.frame) }
            #expect(overlaps(rects).isEmpty, "\(name): \(overlaps(rects))")
            let bounds = CGRect(origin: .zero, size: content).insetBy(dx: -0.5, dy: -0.5)
            for item in plan.items { #expect(bounds.contains(item.frame), "\(name) \(item.control) \(item.frame)") }
        }
    }

    @Test func buttonsKeepMinimumSize() {
        for (name, content) in contentSizes {
            let plan = SlideNumpadPlan(size: content)
            let minHeight: CGFloat = plan.isLandscape ? 34 : 40
            for item in plan.items {
                #expect(item.frame.height >= minHeight, "\(name) \(item.control) h=\(item.frame.height)")
                #expect(item.frame.width >= 34, "\(name) \(item.control) w=\(item.frame.width)")
            }
        }
    }

    @Test func orientationFollowsSize() {
        #expect(SlideNumpadPlan(size: contentSizes[0].size).isLandscape)
        #expect(!SlideNumpadPlan(size: contentSizes[3].size).isLandscape)
    }

    @Test func containsAllControlsAndRealKeypadUsages() {
        let plan = SlideNumpadPlan(size: contentSizes[1].size)
        #expect(plan.items.count == 6 + 6 + 16 + 2)
        let usages = plan.items.compactMap { item -> UInt16? in
            if case let .key(usage, _) = item.control { usage } else { nil }
        }
        let expected: Set<UInt16> = [0x5F, 0x60, 0x61, 0x54, 0x5C, 0x5D, 0x5E, 0x55, 0x59, 0x5A, 0x5B, 0x56, 0x62, 0x63, 0x67, 0x57, 0x2A, 0x58]
        #expect(Set(usages) == expected)
    }
}
