import CoreGraphics
import Testing
@testable import Xdesk

private final class FakeHandle: VirtualDisplayHandle {
    let displayID: CGDirectDisplayID
    init(displayID: CGDirectDisplayID) { self.displayID = displayID }
}

private struct FakeBackend: VirtualDisplayBackend {
    struct Failure: Error {}
    var isAvailable = true
    var fails = false
    var onCreate: (@Sendable (VirtualDisplaySpec) -> Void)?

    func create(_ spec: VirtualDisplaySpec) throws -> any VirtualDisplayHandle {
        onCreate?(spec)
        if fails { throw Failure() }
        return FakeHandle(displayID: 77)
    }
}

@MainActor
@Suite struct VirtualDisplayProviderTests {
    private let spec = VirtualDisplaySpec(pixelWidth: 1920, pixelHeight: 1200, refreshRate: 60, hiDPI: false)

    @Test func usesVirtualDisplayWhenAvailable() {
        let provider = VirtualDisplayProvider(backend: FakeBackend(), mainDisplayID: { 1 })
        let display = provider.acquire(spec)
        #expect(display == AcquiredDisplay(displayID: 77, mode: .extend, fallbackReason: nil))
        #expect(provider.activeDisplay == display)
    }

    @Test func fallsBackToMirrorWhenUnavailable() {
        let provider = VirtualDisplayProvider(backend: FakeBackend(isAvailable: false), mainDisplayID: { 1 })
        let display = provider.acquire(spec)
        #expect(display.mode == .mirror)
        #expect(display.displayID == 1)
        #expect(display.fallbackReason != nil)
    }

    @Test func fallsBackToMirrorWhenCreationThrows() {
        let provider = VirtualDisplayProvider(backend: FakeBackend(fails: true), mainDisplayID: { 5 })
        let display = provider.acquire(spec)
        #expect(display.mode == .mirror)
        #expect(display.displayID == 5)
    }

    @Test func releaseDropsHandleSoVirtualDisplayDies() {
        let provider = VirtualDisplayProvider(backend: FakeBackend(), mainDisplayID: { 1 })
        _ = provider.acquire(spec)
        provider.release()
        #expect(provider.activeDisplay == nil)
    }

    @Test func reacquireReleasesPreviousDisplay() {
        let provider = VirtualDisplayProvider(backend: FakeBackend(), mainDisplayID: { 1 })
        _ = provider.acquire(spec)
        let second = provider.acquire(VirtualDisplaySpec(pixelWidth: 3840, pixelHeight: 2400, refreshRate: 60, hiDPI: true))
        #expect(provider.activeDisplay == second)
    }

    @Test func parsesManualTargets() {
        if case .manual(let host, let port)? = ViewerController.parseManual(" 127.0.0.1:47800 ") {
            #expect(host == "127.0.0.1" && port == 47800)
        } else { Issue.record("expected manual target") }
        for bad in ["", "host", "host:", ":80", "host:0", "host:99999", "a:b:c"] {
            #expect(ViewerController.parseManual(bad) == nil, "\(bad)")
        }
    }

    @Test func viewerStatsComputesLossAndBitrate() {
        var stats = ViewerStats()
        for n: UInt32 in [0, 1, 3, 4] { stats.record(frameNo: n, byteCount: 1250) }
        let window = stats.closeWindow(nowMs: 500)
        #expect(window?.lossPermille == 200)
        #expect(window?.recvKbps == 80)
        #expect(stats.closeWindow(nowMs: 600) == nil)
        // Cửa sổ kế tiếp không có khung nào: không được tràn số / báo mất gói.
        #expect(stats.closeWindow(nowMs: 1000)?.lossPermille == 0)
    }
}
