import Testing
@testable import XdeskMedia

@Suite struct BitrateControllerTests {
    @Test func firstCalmReportOnlyStartsStableWindow() {
        var c = BitrateController(initialKbps: 10_000)
        #expect(c.update(lossPermille: 0, rttMs: 2, nowMs: 0) == nil)
        #expect(c.kbps == 10_000)
    }

    @Test func increasesFivePercentAfterTwoStableSeconds() {
        var c = BitrateController(initialKbps: 10_000)
        _ = c.update(lossPermille: 0, rttMs: 2, nowMs: 0)
        #expect(c.update(lossPermille: 0, rttMs: 2, nowMs: 1_500) == nil)
        #expect(c.update(lossPermille: 0, rttMs: 2, nowMs: 2_000) == 10_500)
        #expect(c.update(lossPermille: 0, rttMs: 2, nowMs: 3_000) == nil)   // cửa sổ mới 2 s
        #expect(c.update(lossPermille: 0, rttMs: 2, nowMs: 4_000) == 11_025)
    }

    @Test func lossAboveTwoPercentCutsByTwentyPercent() {
        var c = BitrateController(initialKbps: 10_000)
        #expect(c.update(lossPermille: 20, rttMs: 2, nowMs: 0) == nil)       // đúng 2% chưa vượt ngưỡng
        #expect(c.update(lossPermille: 21, rttMs: 2, nowMs: 500) == 8_000)
        #expect(c.update(lossPermille: 40, rttMs: 2, nowMs: 1_000) == 6_400)
    }

    @Test func rttGrowthOverThirtyPercentCuts() {
        var c = BitrateController(initialKbps: 20_000)
        _ = c.update(lossPermille: 0, rttMs: 10, nowMs: 0)
        #expect(c.update(lossPermille: 0, rttMs: 12, nowMs: 500) == nil)     // +20%: bình thường
        #expect(c.update(lossPermille: 0, rttMs: 16, nowMs: 1_000) == 16_000) // +60% và ≥ 5 ms
    }

    @Test func tinyLanRttJitterIsIgnored() {
        var c = BitrateController(initialKbps: 20_000)
        _ = c.update(lossPermille: 0, rttMs: 1, nowMs: 0)
        #expect(c.update(lossPermille: 0, rttMs: 3, nowMs: 500) == nil)       // +200% nhưng chỉ 2 ms
    }

    @Test func clampsToFloorAndCeiling() {
        var low = BitrateController(initialKbps: 2_100)
        #expect(low.update(lossPermille: 500, rttMs: 2, nowMs: 0) == 2_000)
        #expect(low.update(lossPermille: 500, rttMs: 2, nowMs: 500) == nil)
        #expect(low.kbps == 2_000)

        var high = BitrateController(initialKbps: 39_900)
        _ = high.update(lossPermille: 0, rttMs: 2, nowMs: 0)
        #expect(high.update(lossPermille: 0, rttMs: 2, nowMs: 2_000) == 40_000)
        #expect(high.update(lossPermille: 0, rttMs: 2, nowMs: 4_000) == nil)
        #expect(BitrateController(initialKbps: 1).kbps == 2_000)
        #expect(BitrateController(initialKbps: 999_999).kbps == 40_000)
    }

    @Test func congestionResetsStableWindow() {
        var c = BitrateController(initialKbps: 10_000)
        _ = c.update(lossPermille: 0, rttMs: 2, nowMs: 0)
        _ = c.update(lossPermille: 100, rttMs: 2, nowMs: 1_900)               // giảm → 8000
        #expect(c.update(lossPermille: 0, rttMs: 2, nowMs: 2_500) == nil)     // mới 600 ms từ lần giảm
        #expect(c.update(lossPermille: 0, rttMs: 2, nowMs: 3_900) == 8_400)
    }
}

@Suite struct BitrateHighRttCeilingTests {
    @Test func highRttClampsDownToFifteenMbps() {
        var c = BitrateController(initialKbps: 30_000)
        #expect(c.update(lossPermille: 0, rttMs: 21, nowMs: 0) == 15_000)
        #expect(c.kbps == 15_000)
    }

    @Test func highRttNeverClimbsAboveCeiling() {
        var c = BitrateController(initialKbps: 14_900)
        _ = c.update(lossPermille: 0, rttMs: 25, nowMs: 0)
        #expect(c.update(lossPermille: 0, rttMs: 25, nowMs: 2_000) == 15_000)
        #expect(c.update(lossPermille: 0, rttMs: 25, nowMs: 4_000) == nil)
        #expect(c.kbps == 15_000)
    }

    @Test func lowRttKeepsLanCeiling() {
        var c = BitrateController(initialKbps: 30_000)
        #expect(c.update(lossPermille: 0, rttMs: 20, nowMs: 0) == nil)       // đúng 20 ms chưa vượt ngưỡng
        #expect(c.update(lossPermille: 0, rttMs: 2, nowMs: 2_000) == 31_500)
    }
}

@Suite struct BitrateRelayCeilingTests {
    @Test func relayRttClampsToRelayCeiling() {
        var c = BitrateController(initialKbps: 10_000)
        #expect(c.update(lossPermille: 0, rttMs: 150, nowMs: 0) == 5_000)
        #expect(c.update(lossPermille: 0, rttMs: 150, nowMs: 2_000) == nil)
        #expect(c.kbps == 5_000)
    }

    @Test func tailscaleDirectKeepsHighRttCeiling() {
        let c = BitrateController(initialKbps: 10_000)
        #expect(c.ceilingKbps(rttMs: 50) == 15_000)
        #expect(c.ceilingKbps(rttMs: 81) == 5_000)
        #expect(c.ceilingKbps(rttMs: 3) == 40_000)
    }
}
