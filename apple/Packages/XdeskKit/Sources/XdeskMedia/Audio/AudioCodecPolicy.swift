import XdeskWire

/// Chọn codec audio phía host (xem `media-packets.md`): PCM trên LAN, AAC-ELD khi đường truyền hẹp.
/// Trễ chống dao động: xuống AAC khi ước lượng < 10 Mb/s, chỉ quay lại PCM khi ≥ 12 Mb/s.
public struct AudioCodecPolicy: Sendable, Equatable {
    public static let aacBelowKbps = 10_000
    public static let pcmAtOrAboveKbps = 12_000

    public private(set) var codec: AudioWireCodec
    private let narrowPath: Bool
    private let available: Set<AudioWireCodec>

    /// `narrowPath`: Tailscale hoặc USB → luôn ưu tiên AAC-ELD. `negotiated`: cờ `audioPCM`/`audioAACELD` trong giao hai bên.
    public init?(negotiated: Capabilities, narrowPath: Bool) {
        let usable = Set(AudioWireCodec.allCases.filter { negotiated.contains($0.capability) })
        guard !usable.isEmpty else { return nil }
        available = usable
        self.narrowPath = narrowPath
        codec = Self.pick(preferAac: narrowPath, from: usable)
    }

    /// Cập nhật theo ước lượng băng thông (kb/s); trả codec hiện hành.
    @discardableResult
    public mutating func update(estimateKbps: Int) -> AudioWireCodec {
        if narrowPath || estimateKbps < Self.aacBelowKbps {
            codec = Self.pick(preferAac: true, from: available)
        } else if estimateKbps >= Self.pcmAtOrAboveKbps {
            codec = Self.pick(preferAac: false, from: available)
        }
        return codec
    }

    private static func pick(preferAac: Bool, from usable: Set<AudioWireCodec>) -> AudioWireCodec {
        let order: [AudioWireCodec] = preferAac ? [.aacEld, .pcm] : [.pcm, .aacEld]
        return order.first(where: usable.contains) ?? .pcm
    }
}
