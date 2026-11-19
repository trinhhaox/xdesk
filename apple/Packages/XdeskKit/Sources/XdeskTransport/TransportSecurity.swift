/// Chế độ bảo mật của phiên. `devPlaintext` chỉ tồn tại ở build Debug: build Release không thể
/// biên dịch/dựng phiên không mã hoá. `encrypted` chạy Noise (xem `SecureHandshake`) trước hello/welcome.
public enum TransportSecurity: Sendable, Equatable {
    #if DEBUG
    case devPlaintext
    #endif
    case encrypted

    /// Ném `encryptionUnavailable` nếu chế độ này không dùng được (hiện luôn dùng được; chốt chặn cho Release nằm ở kiểu).
    func requireAvailable() throws {}
}
