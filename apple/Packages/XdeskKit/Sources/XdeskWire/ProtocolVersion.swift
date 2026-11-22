/// Phiên bản giao thức `major.minor`. Major lệch → từ chối kết nối (`reject{reason:"version"}`).
public struct ProtocolVersion: Sendable, Equatable, Hashable {
    public static let current = ProtocolVersion(major: 1, minor: 0)

    public let major: UInt8
    public let minor: UInt8

    public init(major: UInt8, minor: UInt8) {
        self.major = major
        self.minor = minor
    }

    /// Phân tích "1.0"; `nil` nếu sai định dạng.
    public init?(string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let major = UInt8(parts[0]), let minor = UInt8(parts[1]) else { return nil }
        self.init(major: major, minor: minor)
    }

    public var string: String { "\(major).\(minor)" }

    public func isCompatible(with other: ProtocolVersion) -> Bool { major == other.major }
}

/// Bitmask khả năng; hai bên dùng giao (`intersection`) của hai tập.
public struct Capabilities: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let h264 = Capabilities(rawValue: 1 << 0)
    public static let hevc = Capabilities(rawValue: 1 << 1)
    public static let audioPCM = Capabilities(rawValue: 1 << 2)
    public static let audioAACELD = Capabilities(rawValue: 1 << 3)
    public static let clipboard = Capabilities(rawValue: 1 << 4)
    public static let mediaOverTcp = Capabilities(rawValue: 1 << 5)
    public static let touchInput = Capabilities(rawValue: 1 << 6)
    public static let hotReconfigure = Capabilities(rawValue: 1 << 7)
    public static let videoPause = Capabilities(rawValue: 1 << 8)
    public static let fileTransfer = Capabilities(rawValue: 1 << 9)
    public static let remoteUnlock = Capabilities(rawValue: 1 << 10)
    public static let mediaKeys = Capabilities(rawValue: 1 << 11)
    public static let multiDisplay = Capabilities(rawValue: 1 << 12)
}
