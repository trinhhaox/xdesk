import AppKit
import Testing
import XdeskInput
@testable import Xdesk

@Suite struct ViewerEventMappingTests {
    @Test func modifierMaskMapsEveryFlag() {
        let all: NSEvent.ModifierFlags = [.shift, .control, .option, .command, .capsLock, .function]
        #expect(ViewerEventMapping.modifiers(all).rawValue == 1 | 2 | 4 | 8 | 16 | 32)
        #expect(ViewerEventMapping.modifiers([]).isEmpty)
    }

    @Test func modifierKeyPressAndReleaseFollowFlags() {
        let down = ViewerEventMapping.modifierKeyEvents(macKeyCode: 55, flags: [.command])
        #expect(down.count == 1 && down[0].keyUsage == 0xE3 && down[0].button == 1)
        let up = ViewerEventMapping.modifierKeyEvents(macKeyCode: 55, flags: [])
        #expect(up[0].keyUsage == 0xE3 && up[0].button == 0)
        // Giữ Shift trái, nhả Shift phải: chỉ phím phải nhả.
        let right = ViewerEventMapping.modifierKeyEvents(macKeyCode: 60, flags: [])
        #expect(right[0].keyUsage == 0xE5 && right[0].button == 0)
    }

    @Test func capsLockSendsTap() {
        let events = ViewerEventMapping.modifierKeyEvents(macKeyCode: 57, flags: [.capsLock])
        #expect(events.map(\.button) == [1, 0])
    }

    @Test func nonModifierKeyCodeYieldsNothing() {
        #expect(ViewerEventMapping.modifierKeyEvents(macKeyCode: 0, flags: [.shift]).isEmpty)
    }

    @Test func preciseScrollPassesPixelsThrough() throws {
        let event = try #require(ViewerEventMapping.scrollEvent(deltaX: 3, deltaY: -12.5, precise: true, mods: [.option]))
        #expect(event.dx == 3 && event.dy == -12.5 && event.mods == InputModifiers.option.rawValue)
    }

    @Test func wheelLinesScaleToPoints() throws {
        let event = try #require(ViewerEventMapping.scrollEvent(deltaX: 0, deltaY: 2, precise: false, mods: []))
        #expect(event.dy == 2 * ViewerEventMapping.wheelLinePoints)
    }

    @Test func zeroScrollIsDropped() {
        #expect(ViewerEventMapping.scrollEvent(deltaX: 0, deltaY: 0, precise: true, mods: []) == nil)
    }

    @Test func quitCloseMinimizeHideStayLocal() {
        for code: UInt16 in [12, 13, 46, 4] {
            #expect(ViewerEventMapping.staysLocal(macKeyCode: code, flags: [.command]))
        }
        #expect(!ViewerEventMapping.staysLocal(macKeyCode: 8, flags: [.command]))
        #expect(!ViewerEventMapping.staysLocal(macKeyCode: 12, flags: []))
    }
}
