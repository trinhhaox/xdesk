/// Lỗi của lớp mật mã (Noise, AEAD, gói UDP). Không chứa khoá hay nonce để tránh lộ qua log.
public enum CryptoError: Error, Equatable, Sendable {
    case invalidKeyLength
    case invalidPublicKey
    /// Kết quả DH toàn số 0 (điểm bậc thấp).
    case invalidDiffieHellman
    case missingStaticKey
    case missingRemoteStaticKey
    case missingPresharedKey
    case invalidPresharedKeyLength
    case unexpectedKeyForPattern
    case wrongTurn
    case handshakeComplete
    case handshakeIncomplete
    case messageTooShort
    case messageTooLarge
    case authenticationFailed
    case nonceExhausted
    case invalidLength
    case invalidHandshakePayload
    case invalidHandshakeFrame
    case invalidPairingURI
    case datagramTooShort
    case replayed
    case outsideReplayWindow
    case unknownEpoch
    /// Hai khoá công khai khác nhau trùng dấu vân tay 64 bit (`id`).
    case deviceIdCollision
}
