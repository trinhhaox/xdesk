import CryptoKit
import Foundation
import XdeskWire

/// Một mục clipboard đã chuẩn hoá: văn bản UTF-8 hoặc ảnh PNG.
public struct ClipboardItem: Sendable, Equatable {
    public let kind: ClipKind
    public let data: [UInt8]
    /// SHA-256 hex thường của `data`.
    public let hash: String

    /// Nil nếu rỗng, quá `ClipLimits.maxBytes`, văn bản không phải UTF-8 hợp lệ, hoặc ảnh không phải PNG.
    public init?(kind: ClipKind, data: [UInt8]) {
        guard !data.isEmpty, data.count <= ClipLimits.maxBytes, Self.isWellFormed(kind: kind, data: data) else { return nil }
        self.kind = kind
        self.data = data
        self.hash = Self.sha256Hex(data)
    }

    public init?(text: String) { self.init(kind: .text, data: Array(text.utf8)) }

    public var text: String? { kind == .text ? String(bytes: data, encoding: .utf8) : nil }
    public var size: UInt32 { UInt32(data.count) }

    static func sha256Hex(_ data: [UInt8]) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Dữ liệu từ mạng chỉ được ghi vào clipboard khi đúng định dạng đã khai báo.
    private static func isWellFormed(kind: ClipKind, data: [UInt8]) -> Bool {
        switch kind {
        case .text: String(bytes: data, encoding: .utf8) != nil
        case .image: data.starts(with: pngSignature)
        }
    }
}
