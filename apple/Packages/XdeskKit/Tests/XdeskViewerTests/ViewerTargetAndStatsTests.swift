import Testing
@testable import XdeskViewer

@Suite struct ViewerTargetAndStatsTests {
    @Test func parsesManualHostPort() {
        #expect(ViewerTarget.parse(manual: " 192.168.1.5:47800 ") == .manual(host: "192.168.1.5", port: 47800))
        #expect(ViewerTarget.parse(manual: "mac.local:1") == .manual(host: "mac.local", port: 1))
    }

    @Test(arguments: ["", "host", ":47800", "host:", "host:0", "host:70000", "a:b:1", "host:abc"])
    func rejectsMalformedManual(text: String) {
        #expect(ViewerTarget.parse(manual: text) == nil)
    }

    @Test func statsReportLossFromFrameNumberGaps() throws {
        var stats = ViewerStats()
        for frameNo: UInt32 in [0, 1, 3, 4] { stats.record(frameNo: frameNo, byteCount: 1000) }
        let closed = stats.closeWindow(nowMs: 500)
        let window = try #require(closed)
        #expect(window.lossPermille == 200)
        #expect(window.fps == 8)
        #expect(window.recvKbps == 64)
        // Cửa sổ kế tiếp không có khung nào: không được tràn số / báo mất gói.
        #expect(stats.closeWindow(nowMs: 600) == nil)
        #expect(stats.closeWindow(nowMs: 1000)?.lossPermille == 0)
    }

    @Test func statsWaitForInterval() {
        var stats = ViewerStats()
        stats.record(frameNo: 0, byteCount: 10)
        #expect(stats.closeWindow(nowMs: 100) == nil)
    }
}
