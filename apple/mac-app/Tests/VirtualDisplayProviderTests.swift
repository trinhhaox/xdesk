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
}
