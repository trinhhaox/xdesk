import Testing
import XdeskWire
@testable import XdeskInput

@Suite struct StickyModifiersTests {
    @Test func singleTapArmsForOneKeyThenReleases() {
        var m = StickyModifiers()
        m.tap(.command, nowMs: 0)
        #expect(m.state(of: .command) == .armed && m.active == .command)
        #expect(m.consume() == .command)
        #expect(m.active.isEmpty && m.state(of: .command) == .off)
    }

    @Test func doubleTapLocksAndSurvivesConsume() {
        var m = StickyModifiers()
        m.tap(.shift, nowMs: 0); m.tap(.shift, nowMs: 200)
        #expect(m.state(of: .shift) == .locked)
        #expect(m.consume() == .shift && m.consume() == .shift)
        m.tap(.shift, nowMs: 5000)
        #expect(m.state(of: .shift) == .off)
    }

    @Test func slowSecondTapDisarms() {
        var m = StickyModifiers()
        m.tap(.option, nowMs: 0); m.tap(.option, nowMs: 2000)
        #expect(m.state(of: .option) == .off)
    }

    @Test func modifiersCombineAndResetClearsAll() {
        var m = StickyModifiers()
        m.tap(.command, nowMs: 0); m.tap(.shift, nowMs: 100)
        #expect(m.active == [.command, .shift])
        m.reset()
        #expect(m.active.isEmpty)
    }

    @Test func tappingAnotherModifierBetweenDoesNotLock() {
        var m = StickyModifiers()
        m.tap(.command, nowMs: 0); m.tap(.shift, nowMs: 50); m.tap(.command, nowMs: 100)
        #expect(m.state(of: .command) == .off)
    }
}

@Suite struct VideoPanTests {
    @Test func noPanWhenFocusIsAboveKeyboard() {
        #expect(VideoPan.offset(focusY: 100, viewHeight: 400, obscuredHeight: 200, videoBottom: 400) == 0)
    }

    @Test func pansOnlyAsMuchAsNeeded() {
        #expect(VideoPan.offset(focusY: 250, viewHeight: 400, obscuredHeight: 200, videoBottom: 400) == 78)
    }

    @Test func panIsClampedToKeyboardHeight() {
        #expect(VideoPan.offset(focusY: 399, viewHeight: 400, obscuredHeight: 200, videoBottom: 400) == 200)
    }

    @Test func panStopsAtVideoBottom() {
        #expect(VideoPan.offset(focusY: 390, viewHeight: 600, obscuredHeight: 300, videoBottom: 330) == 30)
    }

    @Test func invalidInputsGiveNoPan() {
        #expect(VideoPan.offset(focusY: .nan, viewHeight: 400, obscuredHeight: 200, videoBottom: 400) == 0)
        #expect(VideoPan.offset(focusY: 300, viewHeight: 400, obscuredHeight: 0, videoBottom: 400) == 0)
    }
}

@Suite struct CharacterUsageTests {
    @Test func lettersDigitsAndSpaceMapToHid() {
        #expect(HidKeyMap.hidUsage(forCharacter: "c") == 0x06)
        #expect(HidKeyMap.hidUsage(forCharacter: "a") == 0x04)
        #expect(HidKeyMap.hidUsage(forCharacter: "1") == 0x1E)
        #expect(HidKeyMap.hidUsage(forCharacter: "0") == 0x27)
        #expect(HidKeyMap.hidUsage(forCharacter: " ") == 0x2C)
    }

    @Test func nonAsciiOrShiftedCharactersAreNotKeys() {
        #expect(HidKeyMap.hidUsage(forCharacter: "ế") == nil)
        #expect(HidKeyMap.hidUsage(forCharacter: "C") == nil)
        #expect(HidKeyMap.hidUsage(forCharacter: "!") == nil)
    }

    @Test func unboundedNormalizeKeepsOutOfFrameDeltas() throws {
        let mapper = try #require(VideoContentMapper(viewWidth: 200, viewHeight: 100, contentWidth: 100, contentHeight: 100))
        let p = mapper.normalizeUnbounded(x: 0, y: 50)
        #expect(p.x == -0.5 && p.y == 0.5)
    }
}
