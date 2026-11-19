package vn.xox.xdesk.crypto

/** Mã lỗi của lớp mật mã, trùng tên với `CryptoError` của bản Swift. Không chứa khoá hay nonce. */
enum class CryptoErrorCode {
    invalidKeyLength,
    invalidPublicKey,
    invalidDiffieHellman,
    missingStaticKey,
    missingRemoteStaticKey,
    missingPresharedKey,
    invalidPresharedKeyLength,
    unexpectedKeyForPattern,
    wrongTurn,
    handshakeComplete,
    handshakeIncomplete,
    messageTooShort,
    messageTooLarge,
    authenticationFailed,
    nonceExhausted,
    invalidLength,
    invalidHandshakePayload,
    invalidHandshakeFrame,
    invalidPairingURI,
    datagramTooShort,
    replayed,
    outsideReplayWindow,
    unknownEpoch,
}

/** Lỗi duy nhất mà module `crypto` được phép ném. */
class CryptoException(val code: CryptoErrorCode) : Exception(code.name)

internal fun cryptoError(code: CryptoErrorCode): Nothing = throw CryptoException(code)
