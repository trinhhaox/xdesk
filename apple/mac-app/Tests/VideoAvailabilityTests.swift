import Foundation
import Testing
@testable import Xdesk

private actor Recorder {
    private(set) var triggers: [VideoRetryPolicy.Trigger] = []
    func add(_ trigger: VideoRetryPolicy.Trigger) -> Int { triggers.append(trigger); return triggers.count }
}

/// Dãy trạng thái thay đổi theo từng lần đo (lần cuối lặp lại).
private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [LockScreenState]
    init(_ states: [LockScreenState]) { queue = states }
    func next() -> LockScreenState { lock.withLock { queue.count > 1 ? queue.removeFirst() : queue[0] } }
}

@Suite struct VideoAvailabilityTests {
    private let open = LockScreenState(locked: false, displayAwake: true)
    private let locked = LockScreenState(locked: true, displayAwake: true)
    private let asleep = LockScreenState(locked: false, displayAwake: false)

    // MARK: Quyết định giữ phiên

    @Test func sleepingOrLockedMacKeepsTheSessionForCaptureFailures() async {
        for state in [asleep, locked, LockScreenState(locked: true, displayAwake: false)] {
            let keep = await VideoAvailability.keepsSession(after: CaptureError.displayNotFound(15), probe: { state })
            #expect(keep, "state \(state)")
        }
    }

    @Test func virtualDisplayCreationFailureWhileAsleepKeepsTheSession() async {
        struct Rejected: Error {}
        #expect(await VideoAvailability.keepsSession(after: Rejected(), probe: { asleep }))
    }

    @Test func genuineFailureOnAnAwakeUnlockedMacStillFails() async {
        #expect(await !VideoAvailability.keepsSession(after: CaptureError.displayNotFound(15), probe: { open }))
        struct EncoderBroke: Error {}
        #expect(await !VideoAvailability.keepsSession(after: EncoderBroke(), probe: { open }))
        #expect(await !VideoAvailability.keepsSession(after: nil, probe: { open }))
    }

    @Test func missingScreenRecordingPermissionIsGenuineEvenWhenLocked() async {
        let keep = await VideoAvailability.keepsSession(
            after: CaptureError.permissionDenied, probe: { locked }, screenRecordingGranted: { false })
        #expect(!keep)
        // Quyền đã cấp mà SCShareableContent vẫn lỗi (do màn hình khoá) thì không phải lỗi quyền.
        let granted = await VideoAvailability.keepsSession(
            after: CaptureError.permissionDenied, probe: { locked }, screenRecordingGranted: { true })
        #expect(granted)
    }

    @Test func graceWindowCatchesASleepFlagThatFlipsJustAfterTheStreamStops() async {
        let probe = Probe([open, open, asleep])
        let keep = await VideoAvailability.keepsSession(
            after: CaptureError.displayNotFound(1), probe: { probe.next() }, grace: .seconds(1), interval: .milliseconds(100), sleep: { _ in })
        #expect(keep)
    }

    @Test func graceWindowExpiresWhenTheMacStaysAwake() async {
        let keep = await VideoAvailability.keepsSession(
            after: CaptureError.displayNotFound(1), probe: { open }, grace: .milliseconds(450), interval: .milliseconds(150), sleep: { _ in })
        #expect(!keep)
    }

    // MARK: Chính sách thử lại

    @Test func wakeSignalsRetryAsSoonAsTheDisplayIsOnEvenIfStillLocked() {
        #expect(VideoRetryPolicy.shouldRetry(.signal, state: locked))
        #expect(VideoRetryPolicy.shouldRetry(.signal, state: open))
        #expect(!VideoRetryPolicy.shouldRetry(.signal, state: asleep))
    }

    @Test func pollOnlyRetriesWhenAwakeAndUnlocked() {
        #expect(VideoRetryPolicy.shouldRetry(.poll, state: open))
        #expect(!VideoRetryPolicy.shouldRetry(.poll, state: locked))
        #expect(!VideoRetryPolicy.shouldRetry(.poll, state: asleep))
    }

    // MARK: Vòng thử lại

    @Test(.timeLimit(.minutes(1))) func signalTriggersAnAttemptAndLoopEndsWhenAttemptSucceeds() async {
        let (signals, continuation) = AsyncStream.makeStream(of: Void.self)
        let recorder = Recorder()
        let loop = Task {
            await VideoRetryLoop.run(signals: signals, poll: .seconds(3600)) { trigger in await recorder.add(trigger) >= 2 }
        }
        continuation.yield()
        continuation.yield()
        await loop.value
        let triggers = await recorder.triggers
        #expect(triggers == [.signal, .signal])
    }

    @Test(.timeLimit(.minutes(1))) func pollIsTheBackupWhenNoSignalArrives() async {
        let (signals, _) = AsyncStream.makeStream(of: Void.self)
        let recorder = Recorder()
        await VideoRetryLoop.run(signals: signals, poll: .milliseconds(20)) { trigger in await recorder.add(trigger) >= 3 }
        let triggers = await recorder.triggers
        #expect(triggers.count >= 3)
        #expect(triggers.allSatisfy { $0 == .poll })
    }

    @Test(.timeLimit(.minutes(1))) func cancellingTheTaskStopsTheLoop() async {
        let (signals, _) = AsyncStream.makeStream(of: Void.self)
        let loop = Task { await VideoRetryLoop.run(signals: signals, poll: .milliseconds(10)) { _ in false } }
        try? await Task.sleep(for: .milliseconds(60))
        loop.cancel()
        await loop.value
    }
}
