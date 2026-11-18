/// Lỗi giải mã/mã hoá Xdesk Wire. Mọi đường giải mã chỉ ném các lỗi này, không trap.
public enum WireError: Error, Sendable, Equatable {
    case truncated(need: Int, have: Int)
    case invalidFrameLength(Int)
    case frameTooLarge(Int)
    case unknownFrameKind(UInt8)
    case unsupportedVersion(UInt8)
    case unknownPacketType(UInt8)
    case unexpectedPacketType(UInt8)
    case invalidFragment(idx: UInt16, cnt: UInt16)
    case fragmentCountTooLarge(UInt16)
    case inconsistentFragmentCount(frameNo: UInt32)
    case payloadTooLarge(Int)
    case emptyPayload
    case invalidNackCount(Int)
    case invalidInput(String)
    case malformedJSON(String)
    case invalidField(String)

    /// Mã ổn định dùng trong test vectors (dùng chung với bản Kotlin).
    public var code: String {
        switch self {
        case .truncated: "truncated"
        case .invalidFrameLength: "invalidFrameLength"
        case .frameTooLarge: "frameTooLarge"
        case .unknownFrameKind: "unknownFrameKind"
        case .unsupportedVersion: "unsupportedVersion"
        case .unknownPacketType: "unknownPacketType"
        case .unexpectedPacketType: "unexpectedPacketType"
        case .invalidFragment: "invalidFragment"
        case .fragmentCountTooLarge: "fragmentCountTooLarge"
        case .inconsistentFragmentCount: "inconsistentFragmentCount"
        case .payloadTooLarge: "payloadTooLarge"
        case .emptyPayload: "emptyPayload"
        case .invalidNackCount: "invalidNackCount"
        case .invalidInput: "invalidInput"
        case .malformedJSON: "malformedJSON"
        case .invalidField: "invalidField"
        }
    }
}
