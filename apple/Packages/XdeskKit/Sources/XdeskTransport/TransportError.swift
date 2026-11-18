/// Lỗi tầng transport (lỗi giải mã wire được ném nguyên dạng `WireError`).
public enum TransportError: Error, Sendable, Equatable {
    case connectionFailed(String)
    case connectionClosed
    case timedOut
    case protocolViolation(String)
    case rejected(reason: String, detail: String?)
    /// Mã hoá chưa sẵn sàng (phase 06) hoặc build Release không cho phép dev-plaintext.
    case encryptionUnavailable
    case listenerFailed(String)
    case noPeer
}
