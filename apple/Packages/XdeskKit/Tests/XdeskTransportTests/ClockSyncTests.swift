import Testing
import XdeskWire
@testable import XdeskTransport

@Suite struct ClockSyncTests {
    /// Host chạy nhanh hơn viewer 1000 ms; đường đi đối xứng 10 ms mỗi chiều, host xử lý 2 ms.
    @Test func recoversKnownOffsetAndRtt() {
        let sample = ClockSample(t0: 100, t1: 1110, t2: 1112, t3: 122)
        #expect(sample.offsetMs == 1000)
        #expect(sample.rttMs == 20)
        #expect(sample.isValid)
    }

    @Test func prefersLowestRttSample() {
        var sync = ClockSync(windowSize: 4)
        #expect(sync.offsetMs == nil)
        sync.add(ClockSample(t0: 0, t1: 1050, t2: 1050, t3: 100))   // rtt 100, lệch bất đối xứng → offset 1000
        sync.add(ClockSample(t0: 200, t1: 1205, t2: 1206, t3: 211)) // rtt 10, offset 1000 chuẩn
        sync.add(ClockSample(t0: 400, t1: 1500, t2: 1500, t3: 600)) // rtt 200, offset 1000 nhưng nhiễu
        #expect(sync.rttMs == 10)
        #expect(sync.offsetMs == 1000)
        #expect(sync.viewerToHostMs(5000) == 6000)
        #expect(sync.hostToViewerMs(6000) == 5000)
    }

    @Test func rejectsInvalidSamples() {
        var sync = ClockSync()
        let hostWentBackwards = sync.add(ClockSample(t0: 100, t1: 90, t2: 80, t3: 120))
        let negativeRtt = sync.add(ClockSample(t0: 100, t1: 100, t2: 300, t3: 150))
        #expect(!hostWentBackwards)
        #expect(!negativeRtt)
        #expect(sync.sampleCount == 0)
    }

    @Test func windowEvictsOldestSamples() {
        var sync = ClockSync(windowSize: 2)
        sync.add(ClockSample(t0: 0, t1: 5, t2: 5, t3: 10))      // rtt 10 (nhỏ nhất) nhưng cũ
        sync.add(ClockSample(t0: 20, t1: 60, t2: 60, t3: 70))
        sync.add(ClockSample(t0: 100, t1: 160, t2: 160, t3: 120))
        #expect(sync.sampleCount == 2)
        #expect(sync.rttMs == 20)
    }

    @Test func makePongEchoesT0() {
        let pong = ClockSync.makePong(for: Ping(t0: 7), receivedAtMs: 10, sentAtMs: 11)
        #expect(pong == Pong(t0: 7, t1: 10, t2: 11))
        #expect(ClockSample(pong: pong, receivedAtMs: 18).rttMs == 10)
    }
}
