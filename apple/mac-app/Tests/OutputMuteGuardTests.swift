import Foundation
import os
import Testing
@testable import Xdesk

private final class FakeMuteBackend: OutputMuteBackend, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<[String: Bool]>
    var uid: String? = "speakers"
    var failMute = false

    init(muted: Bool = false) { state = OSAllocatedUnfairLock(initialState: ["speakers": muted, "headphones": false]) }

    func defaultOutputUID() -> String? { uid }
    func isMuted(uid: String) -> Bool? { state.withLock { $0[uid] } }

    func setMuted(_ muted: Bool, uid: String) -> Bool {
        if failMute { return false }
        return state.withLock { s in
            guard s[uid] != nil else { return false }
            s[uid] = muted
            return true
        }
    }
}

@Suite struct OutputMuteGuardTests {
    private func makeGuard(_ backend: FakeMuteBackend) -> (OutputMuteGuard, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xdesk-mute-\(UUID().uuidString)/audio-mute-restore.json")
        return (OutputMuteGuard(backend: backend, stateURL: url), url)
    }

    @Test func mutesWhileStreamingAndRestoresAtTheEnd() {
        let backend = FakeMuteBackend()
        let (guardian, url) = makeGuard(backend)
        #expect(guardian.engage())
        #expect(backend.isMuted(uid: "speakers") == true)
        #expect(FileManager.default.fileExists(atPath: url.path), "file khôi phục phải có TRƯỚC/trong lúc đang tắt tiếng")
        guardian.release()
        #expect(backend.isMuted(uid: "speakers") == false)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func doesNotTouchAnAlreadyMutedOutput() {
        let backend = FakeMuteBackend(muted: true)
        let (guardian, url) = makeGuard(backend)
        #expect(!guardian.engage())
        #expect(!FileManager.default.fileExists(atPath: url.path))
        guardian.release()
        #expect(backend.isMuted(uid: "speakers") == true, "người dùng tự tắt tiếng thì không được bật lại")
    }

    @Test func lastSessionRestoresNotTheFirst() {
        let backend = FakeMuteBackend()
        let (guardian, _) = makeGuard(backend)
        #expect(guardian.engage())
        #expect(guardian.engage())
        guardian.release()
        #expect(backend.isMuted(uid: "speakers") == true)
        guardian.release()
        #expect(backend.isMuted(uid: "speakers") == false)
    }

    @Test func recoversAfterACrashOnTheNextLaunch() throws {
        let backend = FakeMuteBackend()
        let (crashed, url) = makeGuard(backend)
        #expect(crashed.engage())
        // Tiến trình chết: không release. Lần mở sau dùng cùng file trạng thái.
        let relaunched = OutputMuteGuard(backend: backend, stateURL: url)
        #expect(relaunched.recoverAfterCrash())
        #expect(backend.isMuted(uid: "speakers") == false)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!relaunched.recoverAfterCrash(), "không còn gì để khôi phục")
    }

    @Test func restoresTheDeviceThatWasMutedEvenIfTheDefaultChanged() {
        let backend = FakeMuteBackend()
        let (guardian, _) = makeGuard(backend)
        #expect(guardian.engage())
        backend.uid = "headphones"
        guardian.release()
        #expect(backend.isMuted(uid: "speakers") == false)
        #expect(backend.isMuted(uid: "headphones") == false)
    }

    @Test func failingToMuteLeavesNoStateBehind() {
        let backend = FakeMuteBackend()
        backend.failMute = true
        let (guardian, url) = makeGuard(backend)
        #expect(!guardian.engage())
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!guardian.isMutingOutput)
    }

    @Test func corruptRestoreFileIsDiscardedWithoutTouchingAudio() throws {
        let backend = FakeMuteBackend(muted: true)
        let (guardian, url) = makeGuard(backend)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("không phải json".utf8).write(to: url)
        #expect(!guardian.recoverAfterCrash())
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(backend.isMuted(uid: "speakers") == true)
    }

    @Test func restoreNowIgnoresSessionCount() {
        let backend = FakeMuteBackend()
        let (guardian, _) = makeGuard(backend)
        _ = guardian.engage()
        _ = guardian.engage()
        guardian.restoreNow()
        #expect(backend.isMuted(uid: "speakers") == false)
    }
}
