import AppKit
import Foundation
import os

/// Tuỳ chọn audio của host: "Chỉ phát trên thiết bị" (tắt tiếng loa Mac khi đang stream audio). Mặc định tắt.
final class HostAudioOptions: @unchecked Sendable {
    static let muteLocalOutputKey = "xdesk.host.audioOnlyOnDevice"

    let muteGuard: OutputMuteGuard
    private let flag: OSAllocatedUnfairLock<Bool>
    private let defaults: UserDefaults

    init(
        backend: any OutputMuteBackend = CoreAudioMuteBackend(), stateURL: URL = HostAudioOptions.defaultStateURL(),
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        flag = OSAllocatedUnfairLock(initialState: defaults.bool(forKey: Self.muteLocalOutputKey))
        muteGuard = OutputMuteGuard(backend: backend, stateURL: stateURL)
        // Lần chạy trước có thể chết khi đang tắt tiếng loa → bật lại trước khi làm gì khác.
        muteGuard.recoverAfterCrash()
        let guardRef = muteGuard
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            guardRef.restoreNow()
        }
    }

    var muteLocalOutput: Bool { flag.withLock { $0 } }

    /// `persist: false` chỉ dành cho kiểm thử tự động.
    func setMuteLocalOutput(_ enabled: Bool, persist: Bool = true) {
        flag.withLock { $0 = enabled }
        if persist { defaults.set(enabled, forKey: Self.muteLocalOutputKey) }
    }

    var settings: HostAudioSettings {
        HostAudioSettings(muteGuard: muteGuard, muteLocalOutput: { [self] in muteLocalOutput })
    }

    static func defaultStateURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Xdesk", isDirectory: true).appendingPathComponent("audio-mute-restore.json")
    }
}
