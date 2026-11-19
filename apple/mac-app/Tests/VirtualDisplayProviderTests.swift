import CoreGraphics
import Foundation
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

@MainActor
@Suite struct NativeDisplayTests {
    @Test func acquireNativeUsesMainDisplayWithoutCreatingVirtualOne() {
        let created = CreatedCounter()
        let backend = FakeBackend(onCreate: { _ in created.bump() })
        let provider = VirtualDisplayProvider(backend: backend, mainDisplayID: { 9 })
        let display = provider.acquireNative()
        #expect(display == AcquiredDisplay(displayID: 9, mode: .native, fallbackReason: nil))
        #expect(provider.activeDisplay == display)
        #expect(created.count == 0)
    }

    @Test func acquireNativeReleasesAnEarlierVirtualDisplay() {
        let provider = VirtualDisplayProvider(backend: FakeBackend(), mainDisplayID: { 9 })
        _ = provider.acquire(VirtualDisplaySpec(pixelWidth: 100, pixelHeight: 200, refreshRate: 60, hiDPI: true))
        _ = provider.acquireNative()
        #expect(provider.activeDisplay?.mode == .native)
    }

    @Test(arguments: [
        (2940, 1912, 2560, 1664), (3024, 1964, 2560, 1662), (5120, 2880, 2560, 1440),
        (1920, 1080, 1920, 1080), (1080, 1920, 1080, 1920), (2000, 3001, 1706, 2560),
    ])
    func nativeCaptureSizeKeepsAspectAndCapsLongEdge(w: Int, h: Int, expectedW: Int, expectedH: Int) throws {
        let size = try #require(NativeCaptureSize.fit(pixelWidth: w, pixelHeight: h))
        #expect(size.width == expectedW && size.height == expectedH)
        #expect(size.width % 2 == 0 && size.height % 2 == 0 && max(size.width, size.height) <= NativeCaptureSize.maxLongEdge)
    }

    @Test func nativeCaptureSizeRejectsInvalidDisplays() {
        #expect(NativeCaptureSize.fit(pixelWidth: 0, pixelHeight: 1080) == nil)
        #expect(NativeCaptureSize.fit(pixelWidth: 1920, pixelHeight: -1) == nil)
    }
}

private final class CreatedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func bump() { lock.withLock { value += 1 } }
}
