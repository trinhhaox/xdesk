package vn.xox.xdesk.crypto

import vn.xox.xdesk.crypto.Primitives.hkdf

/** Bốn khoá phiên 32 byte: TCP và UDP tách biệt, mỗi hướng một khoá. `toString` không lộ khoá. */
class SessionKeys(val tcpSend: ByteArray, val tcpReceive: ByteArray, val udpSend: ByteArray, val udpReceive: ByteArray) {
    override fun toString(): String = "SessionKeys(redacted)"

    companion object {
        /** `HKDF-SHA256(ikm = khoá split, salt = handshakeHash, info = nhãn, 32 B)`. */
        fun derive(
            initiatorToResponder: ByteArray,
            responderToInitiator: ByteArray,
            handshakeHash: ByteArray,
            role: NoiseRole,
        ): SessionKeys {
            fun key(ikm: ByteArray, label: String) = hkdf(ikm, handshakeHash, label.toByteArray(), 32)
            val tcpI2R = key(initiatorToResponder, "xdesk v1 tcp i2r")
            val tcpR2I = key(responderToInitiator, "xdesk v1 tcp r2i")
            val udpI2R = key(initiatorToResponder, "xdesk v1 udp i2r")
            val udpR2I = key(responderToInitiator, "xdesk v1 udp r2i")
            return if (role == NoiseRole.INITIATOR) SessionKeys(tcpI2R, tcpR2I, udpI2R, udpR2I)
            else SessionKeys(tcpR2I, tcpI2R, udpR2I, udpI2R)
        }
    }
}

/** Khoá phiên sau khi bắt tay xong; ném `handshakeIncomplete` nếu chưa xong. */
fun NoiseHandshakeState.sessionKeys(): SessionKeys {
    val (i2r, r2i) = splitKeys()
    return SessionKeys.derive(i2r, r2i, handshakeHash, role)
}

internal object KeySchedule {
    /** Khoá kế tiếp khi rekey (một chiều): `HKDF(ikm = K, salt = rỗng, info = "xdesk v1 rekey", 32 B)`. */
    fun next(key: ByteArray): ByteArray = hkdf(key, ByteArray(0), "xdesk v1 rekey".toByteArray(), 32)
}
