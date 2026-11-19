import Testing
import XdeskWire
@testable import XdeskInput

@Suite struct PointerSettingsTests {
    @Test func defaultsKeepDirectBehaviour() {
        let s = PointerSettings()
        #expect(s.mode == .direct && s.speed == 1 && s.naturalScroll && s.longPressRightClick)
    }

    @Test func speedIsClampedAndNonFiniteFallsBack() {
        #expect(PointerSettings(speed: 99).speed == PointerSettings.speedRange.upperBound)
        #expect(PointerSettings(speed: 0).speed == PointerSettings.speedRange.lowerBound)
        #expect(PointerSettings(speed: .nan).speed == 1)
        var s = PointerSettings()
        s.speed = -3
        #expect(s.speed == PointerSettings.speedRange.lowerBound)
    }

    @Test func accelerationCurveIsMonotonicAndCapped() {
        let gains = [Float(0), 0.1, 0.5, 1, 2, 10].map { PointerAcceleration.gain(velocity: $0, speed: 1) }
        #expect(gains == gains.sorted())
        #expect(gains[0] == PointerAcceleration.baseGain)
        #expect(gains.last == PointerAcceleration.maxGain)
        #expect(PointerAcceleration.gain(velocity: -5, speed: 1) == PointerAcceleration.baseGain)
        #expect(PointerAcceleration.gain(velocity: .infinity, speed: 1) == PointerAcceleration.baseGain)
    }

    @Test func speedMultipliesGain() {
        #expect(PointerAcceleration.gain(velocity: 0.4, speed: 2) == 2 * PointerAcceleration.gain(velocity: 0.4, speed: 1))
    }

    @Test func engineUsesTrackpadOnlyWhenAsked() {
        var direct = PointerEngine(settings: PointerSettings(), surfaceWidth: 1000, surfaceHeight: 500)
        var pad = PointerEngine(settings: PointerSettings(mode: .trackpad), surfaceWidth: 1000, surfaceHeight: 500, cursor: (0.25, 0.75))
        #expect(direct.cursor == nil)
        #expect(pad.cursor?.x == 0.25 && pad.cursor?.y == 0.75)
        let begin = TouchSample(id: 1, x: 0.9, y: 0.9, phase: .began, timeMs: 0)
        let end = TouchSample(id: 1, x: 0.9, y: 0.9, phase: .ended, timeMs: 50)
        _ = direct.handle(begin); _ = pad.handle(begin)
        #expect(direct.handle(end)[1].x == 0.9, "trực tiếp: click tại ngón")
        #expect(pad.handle(end)[1].x == 0.25, "trackpad: click tại con trỏ")
    }

    @Test func engineLongPressSettingReachesDirectMode() {
        var engine = PointerEngine(settings: PointerSettings(longPressRightClick: false), surfaceWidth: 1000, surfaceHeight: 500)
        _ = engine.handle(TouchSample(id: 1, x: 0.5, y: 0.5, phase: .began, timeMs: 0))
        #expect(engine.tick(nowMs: 5000).isEmpty)
    }

    @Test func engineNaturalScrollSettingReachesDirectMode() {
        var engine = PointerEngine(settings: PointerSettings(naturalScroll: false), surfaceWidth: 1000, surfaceHeight: 500)
        _ = engine.handle(TouchSample(id: 1, x: 0.4, y: 0.5, phase: .began, timeMs: 0))
        _ = engine.handle(TouchSample(id: 2, x: 0.6, y: 0.5, phase: .began, timeMs: 1))
        _ = engine.handle(TouchSample(id: 1, x: 0.4, y: 0.6, phase: .moved, timeMs: 20))
        let out = engine.handle(TouchSample(id: 2, x: 0.6, y: 0.6, phase: .moved, timeMs: 20))
        #expect(out.first?.dy ?? 0 < 0)
    }
}
