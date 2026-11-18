import Testing
@testable import XdeskCrypto

struct ReplayWindowTests {
    @Test func firstPacketAndDuplicates() {
        var window = ReplayWindow()
        #expect(window.verdict(for: 0) == .fresh)
        window.accept(0)
        #expect(window.verdict(for: 0) == .duplicate)
        #expect(window.verdict(for: 1) == .fresh)
    }

    @Test func reorderingWithinWindow() {
        var window = ReplayWindow()
        window.accept(10)
        for n: UInt64 in [9, 5, 0] {
            #expect(window.verdict(for: n) == .fresh)
            window.accept(n)
            #expect(window.verdict(for: n) == .duplicate)
        }
        #expect(window.verdict(for: 10) == .duplicate)
    }

    @Test func tooOldAndWindowEdge() {
        var window = ReplayWindow()
        window.accept(2000)
        #expect(window.verdict(for: 2000 - 1023) == .fresh)
        #expect(window.verdict(for: 2000 - 1024) == .tooOld)
        #expect(window.verdict(for: 0) == .tooOld)
    }

    @Test func slidingForgetsEvictedSlots() {
        var window = ReplayWindow()
        window.accept(5)
        window.accept(5 + 1024)
        #expect(window.verdict(for: 5) == .tooOld)
        // slot của 5 được tái sử dụng cho 1029: gói lân cận 1030 phải còn "tươi", 1029 là trùng.
        #expect(window.verdict(for: 5 + 1024 + 1) == .fresh)
        window.accept(1030)
        #expect(window.verdict(for: 1029) == .duplicate)
        #expect(window.verdict(for: 1028) == .fresh)
    }

    @Test func largeJumpClearsEverything() {
        var window = ReplayWindow()
        for n in 0..<100 { window.accept(UInt64(n)) }
        window.accept(1_000_000)
        #expect(window.verdict(for: 1_000_000) == .duplicate)
        #expect(window.verdict(for: 999_999) == .fresh)
        #expect(window.verdict(for: 99) == .tooOld)
    }
}
