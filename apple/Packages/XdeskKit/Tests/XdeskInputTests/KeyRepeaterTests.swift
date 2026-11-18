import Testing
@testable import XdeskInput

@Suite struct KeyRepeaterTests {
    private let keyA: UInt16 = 4
    private let leftShift: UInt16 = 0xE1

    @Test func repeatsOnlyAfterInitialDelay() {
        var r = KeyRepeater()
        r.keyDown(usage: keyA, mods: [.shift], nowMs: 1000)
        #expect(r.tick(nowMs: 1399).isEmpty)
        let first = r.tick(nowMs: 1400)
        #expect(first.count == 1 && first[0].kind == .key && first[0].keyUsage == keyA && first[0].button == 1)
        #expect(first[0].mods == InputModifiers.shift.rawValue)
        #expect(r.tick(nowMs: 1420).isEmpty)
        #expect(r.tick(nowMs: 1433).count == 1)
    }

    @Test func ratesAroundThirtyPerSecond() {
        var r = KeyRepeater()
        r.keyDown(usage: keyA, mods: [], nowMs: 0)
        var total = 0
        var now: Int64 = 0
        while now <= 1400 { total += r.tick(nowMs: now).count; now += 50 }
        // 1 giây lặp sau độ trễ 400 ms: ~30 lần/s, tick 50 ms bù bằng burst.
        #expect((18...32).contains(total))
    }

    @Test func releaseStopsRepeat() {
        var r = KeyRepeater()
        r.keyDown(usage: keyA, mods: [], nowMs: 0)
        r.keyUp(usage: keyA)
        #expect(!r.isRepeating)
        #expect(r.tick(nowMs: 5000).isEmpty)
    }

    @Test func modifiersNeverRepeat() {
        var r = KeyRepeater()
        r.keyDown(usage: leftShift, mods: [.shift], nowMs: 0)
        #expect(!r.isRepeating)
        #expect(r.tick(nowMs: 5000).isEmpty)
    }

    @Test func latestKeyWinsAndOldKeyUpIsIgnored() {
        var r = KeyRepeater()
        r.keyDown(usage: keyA, mods: [], nowMs: 0)
        r.keyDown(usage: 5, mods: [], nowMs: 100)
        r.keyUp(usage: keyA)
        #expect(r.tick(nowMs: 500)[0].keyUsage == 5)
        r.releaseAll()
        #expect(r.tick(nowMs: 900).isEmpty)
    }

    @Test func longStallIsCappedToSmallBurst() {
        var r = KeyRepeater()
        r.keyDown(usage: keyA, mods: [], nowMs: 0)
        #expect(r.tick(nowMs: 60_000).count <= 4)
    }
}
