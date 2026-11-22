import Testing
import XdeskWire
@testable import XdeskInput

@Suite struct MacKeyboardControllerTests {
    private func key(_ usage: UInt16) -> MacKey { MacKeyboardLayout.allKeys.first { $0.usage == usage }! }
    private let shiftL: UInt16 = 0xE1, cmdL: UInt16 = 0xE3, keyC: UInt16 = 0x06, keyA: UInt16 = 0x04

    private func summary(_ events: [InputEvent]) -> [String] {
        events.map { "\($0.keyUsage)\($0.button == 1 ? "v" : "^")" }
    }

    @Test func plainKeyDownOnPressUpOnRelease() {
        var kb = MacKeyboardController()
        let down = kb.press(touchId: 1, key: key(keyA), nowMs: 0)
        #expect(summary(down) == ["4v"])
        #expect(kb.pressedUsages == [keyA])
        let up = kb.release(touchId: 1, nowMs: 50)
        #expect(summary(up) == ["4^"])
        #expect(kb.pressedUsages.isEmpty)
    }

    @Test func oneShotModifierAppliesToNextKeyThenReleasesAfterKeyUp() {
        var kb = MacKeyboardController()
        #expect(summary(kb.press(touchId: 1, key: key(cmdL), nowMs: 0)) == ["227v"])
        #expect(kb.release(touchId: 1, nowMs: 80).isEmpty)
        #expect(kb.state(ofModifierUsage: cmdL) == .armed)

        let down = kb.press(touchId: 2, key: key(keyC), nowMs: 1000)
        #expect(down[0].mods == InputModifiers.command.rawValue)
        #expect(kb.state(ofModifierUsage: cmdL) == .off)
        #expect(summary(kb.release(touchId: 2, nowMs: 1060)) == ["6^", "227^"])
        // phím kế tiếp không còn ⌘
        let next = kb.press(touchId: 3, key: key(keyC), nowMs: 2000)
        #expect(next[0].mods == 0)
    }

    @Test func doubleTapLocksUntilTappedAgain() {
        var kb = MacKeyboardController()
        _ = kb.press(touchId: 1, key: key(shiftL), nowMs: 0)
        _ = kb.release(touchId: 1, nowMs: 50)
        #expect(kb.press(touchId: 2, key: key(shiftL), nowMs: 200).isEmpty)
        _ = kb.release(touchId: 2, nowMs: 240)
        #expect(kb.state(ofModifierUsage: shiftL) == .locked)

        for id in 3...4 {
            let down = kb.press(touchId: id, key: key(keyA), nowMs: Int64(id) * 1000)
            #expect(down[0].mods == InputModifiers.shift.rawValue)
            _ = kb.release(touchId: id, nowMs: Int64(id) * 1000 + 40)
        }
        #expect(kb.state(ofModifierUsage: shiftL) == .locked)

        #expect(summary(kb.press(touchId: 5, key: key(shiftL), nowMs: 9000)) == ["225^"])
        #expect(kb.state(ofModifierUsage: shiftL) == .off)
    }

    @Test func slowSecondTapKeepsArmedThenQuickLiftCancels() {
        var kb = MacKeyboardController()
        _ = kb.press(touchId: 1, key: key(shiftL), nowMs: 0)
        _ = kb.release(touchId: 1, nowMs: 50)
        #expect(kb.press(touchId: 2, key: key(shiftL), nowMs: 900).isEmpty)
        #expect(kb.state(ofModifierUsage: shiftL) == .armed)
        #expect(summary(kb.release(touchId: 2, nowMs: 950)) == ["225^"])
        #expect(kb.state(ofModifierUsage: shiftL) == .off)
    }

    @Test func slowSecondTapThenChordReleasesAfterKey() {
        var kb = MacKeyboardController()
        _ = kb.press(touchId: 1, key: key(shiftL), nowMs: 0)
        _ = kb.release(touchId: 1, nowMs: 50)
        _ = kb.press(touchId: 2, key: key(shiftL), nowMs: 900)
        let down = kb.press(touchId: 3, key: key(keyA), nowMs: 950)
        #expect(down[0].mods == InputModifiers.shift.rawValue)
        #expect(summary(kb.release(touchId: 3, nowMs: 990)) == ["4^"])
        #expect(summary(kb.release(touchId: 2, nowMs: 1000)) == ["225^"])
    }

    @Test func rearmedModifierSurvivesConsumingKeyLift() {
        var kb = MacKeyboardController()
        _ = kb.press(touchId: 1, key: key(cmdL), nowMs: 0)
        _ = kb.release(touchId: 1, nowMs: 30)
        _ = kb.press(touchId: 2, key: key(keyC), nowMs: 100)
        _ = kb.press(touchId: 3, key: key(cmdL), nowMs: 2000)
        _ = kb.release(touchId: 3, nowMs: 2030)
        #expect(kb.state(ofModifierUsage: cmdL) == .armed)
        #expect(summary(kb.release(touchId: 2, nowMs: 2100)) == ["6^"])
        #expect(kb.state(ofModifierUsage: cmdL) == .armed)
    }

    @Test func holdWithAnotherFingerIsMomentaryChord() {
        var kb = MacKeyboardController()
        _ = kb.press(touchId: 1, key: key(cmdL), nowMs: 0)
        let down = kb.press(touchId: 2, key: key(keyC), nowMs: 100)
        #expect(down[0].mods == InputModifiers.command.rawValue)
        // phím thường nhả trước: ⌘ vẫn đang giữ
        #expect(summary(kb.release(touchId: 2, nowMs: 150)) == ["6^"])
        #expect(kb.state(ofModifierUsage: cmdL) == .armed)
        // nhấc ⌘: tổ hợp đã dùng nên nhả luôn, dù chạm ngắn
        #expect(summary(kb.release(touchId: 1, nowMs: 200)) == ["227^"])
        #expect(kb.state(ofModifierUsage: cmdL) == .off)
    }

    @Test func longHoldWithoutChordReleasesOnLift() {
        var kb = MacKeyboardController()
        _ = kb.press(touchId: 1, key: key(shiftL), nowMs: 0)
        #expect(summary(kb.release(touchId: 1, nowMs: 800)) == ["225^"])
        #expect(kb.activeMods.isEmpty)
    }

    @Test func capsLockTogglesAndTagsLaterKeys() {
        var kb = MacKeyboardController()
        #expect(kb.press(touchId: 1, key: key(0x39), nowMs: 0).isEmpty)
        #expect(kb.release(touchId: 1, nowMs: 30).isEmpty)
        #expect(kb.capsLockOn)
        let down = kb.press(touchId: 2, key: key(keyA), nowMs: 100)
        #expect(down[0].mods == InputModifiers.capsLock.rawValue)
        _ = kb.release(touchId: 2, nowMs: 140)
        _ = kb.press(touchId: 3, key: key(0x39), nowMs: 500)
        #expect(!kb.capsLockOn)
    }

    @Test func capsLockSurvivesReleaseAllUntilCleared() {
        var kb = MacKeyboardController()
        _ = kb.press(touchId: 1, key: key(0x39), nowMs: 0)
        _ = kb.releaseAll()
        #expect(kb.capsLockOn)
        kb.clearCapsLock()
        #expect(!kb.capsLockOn)
    }

    @Test func holdingKeyRepeatsLikeHardwarePath() {
        var kb = MacKeyboardController()
        _ = kb.press(touchId: 1, key: key(keyA), nowMs: 0)
        #expect(kb.isRepeating)
        #expect(kb.tick(nowMs: 399).isEmpty)
        #expect(!kb.tick(nowMs: 400).isEmpty)
        _ = kb.release(touchId: 1, nowMs: 450)
        #expect(!kb.isRepeating)
    }

    @Test func modifiersNeverRepeat() {
        var kb = MacKeyboardController()
        _ = kb.press(touchId: 1, key: key(cmdL), nowMs: 0)
        #expect(!kb.isRepeating)
    }

    @Test func releaseAllFreesKeysAndLockedModifiers() {
        var kb = MacKeyboardController()
        _ = kb.press(touchId: 1, key: key(shiftL), nowMs: 0)
        _ = kb.release(touchId: 1, nowMs: 30)
        _ = kb.press(touchId: 2, key: key(shiftL), nowMs: 100)
        _ = kb.release(touchId: 2, nowMs: 130)
        _ = kb.press(touchId: 3, key: key(cmdL), nowMs: 200)
        _ = kb.press(touchId: 4, key: key(keyA), nowMs: 250)
        let ups = kb.releaseAll()
        #expect(Set(summary(ups)) == ["4^", "225^", "227^"])
        #expect(ups.allSatisfy { $0.button == 0 })
        #expect(kb.pressedUsages.isEmpty && kb.activeMods.isEmpty && !kb.isRepeating)
        #expect(kb.releaseAll().isEmpty)
        // chạm lên muộn của ngón cũ không phát gì
        #expect(kb.release(touchId: 4, nowMs: 300).isEmpty)
    }

    @Test func consumedModifierStillReleasedByReleaseAllBeforeKeyUp() {
        var kb = MacKeyboardController()
        _ = kb.press(touchId: 1, key: key(cmdL), nowMs: 0)
        _ = kb.release(touchId: 1, nowMs: 30)
        _ = kb.press(touchId: 2, key: key(keyC), nowMs: 100)
        #expect(Set(summary(kb.releaseAll())) == ["6^", "227^"])
    }
}
