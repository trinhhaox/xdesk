import Foundation
import XdeskCrypto
import XdeskMedia
import XdeskTransport
import XdeskWire

/// Cài đặt audio phía host cho một phiên (do `HostController` cấp).
struct HostAudioSettings: Sendable {
    /// Tắt tiếng loa Mac khi đang stream audio ("Chỉ phát trên thiết bị"); nil = không có tính năng.
    var muteGuard: OutputMuteGuard?
    var muteLocalOutput: @Sendable () -> Bool = { false }
}

extension HostSession {
    /// Tạo bộ phát audio nếu đã thương lượng được codec. Đường Tailscale/USB (băng thông hẹp) ưu tiên AAC-ELD.
    func makeAudioStreamer(caps: Capabilities, channel: UdpMediaChannel) async -> HostAudioStreamer? {
        var narrow = connection.isUsbTunnel || InterfaceFilter.isTailscale(connection.remoteEndpoint)
        #if DEBUG
        if CommandLine.arguments.contains("--audio-narrow") { narrow = true }
        #endif
        let key = await connection.peer?.publicKey
        let lookup = permissionLookup
        let snapshot = permissions.audio
        let streamer = HostAudioStreamer(negotiated: caps, narrowPath: narrow, streamId: Self.streamId, channel: channel) {
            guard let key, let live = await lookup(key) else { return snapshot }
            return live.audio
        }
        if streamer != nil, audioSettings.muteLocalOutput() { mutedLocalOutput = audioSettings.muteGuard?.engage() ?? false }
        return streamer
    }

    func stopAudio() {
        audio?.stop()
        audio = nil
        if mutedLocalOutput { audioSettings.muteGuard?.release() }
        mutedLocalOutput = false
    }
}
