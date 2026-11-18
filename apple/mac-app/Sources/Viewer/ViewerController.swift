import Foundation
import Observation
import XdeskTransport
import XdeskWire

enum ViewerTarget: Sendable {
    case discovered(DiscoveredHost)
    case manual(host: String, port: UInt16)
}

/// Danh sách host Bonjour + vòng đời kết nối viewer (một cửa sổ video tại một thời điểm).
@MainActor
@Observable
final class ViewerController {
    struct Options {
        var retina = false
        var fullScreen = false
        var latencyOverlay = false
    }

    private(set) var hosts: [DiscoveredHost] = []
    private(set) var session: ViewerSession?
    private(set) var errorMessage: String?
    var options = Options()

    @ObservationIgnored private var browseTask: Task<Void, Never>?
    @ObservationIgnored private var window: ViewerWindow?

    var isConnecting: Bool { session?.state == .connecting }

    func startBrowsing() {
        guard browseTask == nil else { return }
        browseTask = Task { [weak self] in
            for await list in BonjourBrowser().hosts() { self?.hosts = list }
        }
    }

    func stopBrowsing() {
        browseTask?.cancel()
        browseTask = nil
    }

    /// `host:port` (IPv4/tên miền). Trả `nil` nếu sai định dạng.
    static func parseManual(_ text: String) -> ViewerTarget? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, let port = UInt16(parts[1]), port > 0 else { return nil }
        return .manual(host: String(parts[0]), port: port)
    }

    func connect(to target: ViewerTarget, title: String) async {
        guard session == nil else { return }
        errorMessage = nil
        let session = ViewerSession()
        self.session = session
        await session.connect(to: target, config: displayConfig())
        guard case .streaming = session.state else {
            if case .failed(let message) = session.state { errorMessage = message }
            self.session = nil
            return
        }
        window = ViewerWindow(
            session: session, title: title, fullScreen: options.fullScreen, latencyOverlay: options.latencyOverlay,
            onClose: { [weak self] in Task { await self?.disconnect() } }
        )
    }

    func disconnect() async {
        let current = session
        session = nil
        window?.close()
        window = nil
        await current?.disconnect()
    }

    private func displayConfig() -> DisplayConfig {
        options.retina
            ? DisplayConfig(w: 3840, h: 2400, scale: 2, fps: 60, codec: .h264)
            : DisplayConfig(w: 1920, h: 1200, scale: 1, fps: 60, codec: .h264)
    }
}
