import XdeskWire

/// Cấu hình bộ mã hoá video. `bitrateKbps` đổi được lúc chạy (`VideoEncoder.setBitrate`).
public struct EncoderSettings: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var fps: Int
    public var bitrateKbps: Int
    public var codec: VideoCodec
    /// Khoảng keyframe dài vì đã có NACK + `keyframe.request`.
    public var keyframeIntervalSeconds: Int

    public init(width: Int, height: Int, fps: Int = 60, bitrateKbps: Int = 8000, codec: VideoCodec = .h264, keyframeIntervalSeconds: Int = 5) {
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrateKbps = bitrateKbps
        self.codec = codec
        self.keyframeIntervalSeconds = keyframeIntervalSeconds
    }

    public func validate() throws {
        guard (16...16384).contains(width), (16...16384).contains(height) else { throw MediaError.invalidSettings("size \(width)x\(height)") }
        guard (1...240).contains(fps) else { throw MediaError.invalidSettings("fps \(fps)") }
        guard (100...200_000).contains(bitrateKbps) else { throw MediaError.invalidSettings("bitrate \(bitrateKbps)") }
        guard (1...60).contains(keyframeIntervalSeconds) else { throw MediaError.invalidSettings("keyframe interval") }
    }
}
