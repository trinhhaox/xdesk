import CryptoKit

/// Bốn khoá phiên dẫn xuất từ kết quả bắt tay: TCP và UDP tách biệt, mỗi hướng một khoá.
public struct SessionKeys: Sendable, Redacted {
    public let tcpSend: SymmetricKey
    public let tcpReceive: SymmetricKey
    public let udpSend: SymmetricKey
    public let udpReceive: SymmetricKey

    /// `HKDF-SHA256(ikm: khoá split, salt: handshakeHash, info: nhãn)`; nhãn xem `crypto-handshake.md`.
    public static func derive(
        initiatorToResponder: SymmetricKey,
        responderToInitiator: SymmetricKey,
        handshakeHash: [UInt8],
        role: NoiseRole
    ) -> SessionKeys {
        func key(_ ikm: SymmetricKey, _ label: String) -> SymmetricKey {
            HKDF<SHA256>.deriveKey(
                inputKeyMaterial: ikm, salt: handshakeHash, info: Array(label.utf8), outputByteCount: 32)
        }
        let tcpI2R = key(initiatorToResponder, "xdesk v1 tcp i2r")
        let tcpR2I = key(responderToInitiator, "xdesk v1 tcp r2i")
        let udpI2R = key(initiatorToResponder, "xdesk v1 udp i2r")
        let udpR2I = key(responderToInitiator, "xdesk v1 udp r2i")
        switch role {
        case .initiator:
            return SessionKeys(tcpSend: tcpI2R, tcpReceive: tcpR2I, udpSend: udpI2R, udpReceive: udpR2I)
        case .responder:
            return SessionKeys(tcpSend: tcpR2I, tcpReceive: tcpI2R, udpSend: udpR2I, udpReceive: udpI2R)
        }
    }
}

extension NoiseHandshakeState {
    /// Khoá phiên sau khi bắt tay xong; ném `handshakeIncomplete` nếu chưa xong.
    public func sessionKeys() throws -> SessionKeys {
        let keys = try splitKeys()
        return SessionKeys.derive(
            initiatorToResponder: keys.initiatorToResponder, responderToInitiator: keys.responderToInitiator,
            handshakeHash: handshakeHash, role: role)
    }
}

enum KeySchedule {
    /// Khoá kế tiếp khi rekey (một chiều: khoá cũ không suy ra được từ khoá mới).
    static func next(_ key: SymmetricKey) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key, salt: [], info: Array("xdesk v1 rekey".utf8), outputByteCount: 32)
    }
}
