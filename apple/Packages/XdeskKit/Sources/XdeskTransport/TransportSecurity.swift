/// Chế độ bảo mật của phiên. `devPlaintext` chỉ tồn tại ở build Debug: build Release không thể
/// biên dịch/dựng phiên không mã hoá. `encrypted` chờ Noise ở phase 06.
public enum TransportSecurity: Sendable, Equatable {
    #if DEBUG
    case devPlaintext
    #endif
    case encrypted

    /// Ném `encryptionUnavailable` nếu chế độ này chưa dùng được.
    func requireAvailable() throws {
        switch self {
        #if DEBUG
        case .devPlaintext: return
        #endif
        case .encrypted: throw TransportError.encryptionUnavailable
        }
    }
}
