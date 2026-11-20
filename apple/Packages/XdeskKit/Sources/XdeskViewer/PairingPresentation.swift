import Foundation
import XdeskCrypto

/// Nhãn trạng thái ghép đôi của một host trong danh sách (Mac và iOS dùng chung).
public enum HostBadge: Sendable, Equatable {
    case paired
    case unpaired
    case keyChanged

    public var title: String {
        switch self {
        case .paired: String(localized: "Đã ghép", bundle: .module)
        case .unpaired: String(localized: "Chưa ghép", bundle: .module)
        case .keyChanged: String(localized: "Khoá đã đổi", bundle: .module)
        }
    }
}

extension ViewerTrust.HostState {
    public var badge: HostBadge {
        switch self {
        case .paired: .paired
        case .unknown: .unpaired
        case .keyChanged: .keyChanged
        }
    }

    /// Chỉ host đã ghép mới kết nối thẳng; host lạ phải ghép trước, host đổi khoá bị chặn hẳn.
    public var canReconnect: Bool {
        if case .paired = self { true } else { false }
    }
}

public enum PairingInputError: Error, Equatable, LocalizedError {
    case empty
    case notXdesk
    case malformed

    public var errorDescription: String? {
        switch self {
        case .empty: String(localized: "Chưa có liên kết ghép đôi.", bundle: .module)
        case .notXdesk: String(localized: "Mã này không phải mã ghép đôi của Xdesk. Hãy quét mã trong cửa sổ \"Ghép đôi thiết bị mới\" trên Mac.", bundle: .module)
        case .malformed: String(localized: "Mã ghép đôi bị hỏng hoặc không đầy đủ. Hãy tạo mã mới trên Mac rồi quét lại.", bundle: .module)
        }
    }
}

/// Chuyển nội dung quét/dán thành `PairingURI`; lỗi nêu rõ nguyên nhân để hiện cho người dùng.
public enum PairingInput {
    public static func parse(_ text: String) -> Result<PairingURI, PairingInputError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.lowercased().hasPrefix("xdesk://pair") else { return .failure(.notXdesk) }
        do { return .success(try PairingURI.parse(trimmed)) } catch { return .failure(.malformed) }
    }
}
