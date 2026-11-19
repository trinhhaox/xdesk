package vn.xox.xdesk.crypto

/**
 * HandshakeState của Noise (rev 34 §5.3). Mỗi message được áp dụng kiểu "tất cả hoặc không gì":
 * lỗi giữa chừng khôi phục trạng thái cũ. Không thread-safe.
 *
 * `staticPrivateKey` là 32 byte khoá tĩnh X25519 (không rời thiết bị). Khoá thô không bao giờ nằm trong `toString`.
 */
class NoiseHandshakeState internal constructor(
    val pattern: NoisePattern,
    val role: NoiseRole,
    private val staticPrivateKey: ByteArray,
    remoteStaticKey: ByteArray?,
    private val psk: ByteArray?,
    prologue: ByteArray,
    private val ephemeralOverride: ByteArray?,
    private val allowFirstMessagePayload: Boolean,
) {
    constructor(
        pattern: NoisePattern,
        role: NoiseRole,
        staticPrivateKey: ByteArray,
        remoteStaticKey: ByteArray? = null,
        psk: ByteArray? = null,
        prologue: ByteArray = DEFAULT_PROLOGUE,
    ) : this(pattern, role, staticPrivateKey, remoteStaticKey, psk, prologue, null, false)

    private val staticPublicKey: ByteArray = Primitives.x25519PublicKey(staticPrivateKey)
    private var symmetric = NoiseSymmetricState(pattern.protocolName)
    private var ephemeralPrivate: ByteArray? = null
    private var remoteStatic: ByteArray? = null
    private var remoteEphemeral: ByteArray? = null
    private var nextMessage = 0

    /** Hash ngay sau message 2: đầu vào của `ShortAuthString.code`. */
    var messageTwoHash: ByteArray? = null
        private set

    init {
        if (pattern.usesPresharedKey) {
            if (psk == null) cryptoError(CryptoErrorCode.missingPresharedKey)
            if (psk.size != KEY_LENGTH) cryptoError(CryptoErrorCode.invalidPresharedKeyLength)
        } else if (psk != null) {
            cryptoError(CryptoErrorCode.unexpectedKeyForPattern)
        }
        val needsRemote = pattern.initiatorKnowsResponderStatic && role == NoiseRole.INITIATOR
        if (needsRemote && remoteStaticKey == null) cryptoError(CryptoErrorCode.missingRemoteStaticKey)
        if (!needsRemote && remoteStaticKey != null) cryptoError(CryptoErrorCode.unexpectedKeyForPattern)
        if (remoteStaticKey != null && remoteStaticKey.size != KEY_LENGTH) cryptoError(CryptoErrorCode.invalidPublicKey)
        if (staticPrivateKey.size != KEY_LENGTH) cryptoError(CryptoErrorCode.invalidKeyLength)
        remoteStatic = remoteStaticKey?.copyOf()
        symmetric.mixHash(prologue)
        if (pattern.initiatorKnowsResponderStatic) {
            // Pre-message `<- s`: cả hai bên băm khoá tĩnh của responder.
            symmetric.mixHash((if (role == NoiseRole.INITIATOR) remoteStatic else staticPublicKey) ?: ByteArray(0))
        }
    }

    val isComplete: Boolean get() = nextMessage == pattern.messageCount
    val handshakeHash: ByteArray get() = symmetric.hash.copyOf()
    /** Khoá tĩnh của đối tác; có sau khi đọc message mang `s` (hoặc ngay từ đầu với initiator IK). */
    val remoteStaticKey: ByteArray? get() = remoteStatic?.copyOf()
    val remoteEphemeralKey: ByteArray? get() = remoteEphemeral?.copyOf()
    val localEphemeralKey: ByteArray? get() = ephemeralPrivate?.let(Primitives::x25519PublicKey)

    private val isMyTurnToWrite: Boolean get() = (nextMessage % 2 == 0) == (role == NoiseRole.INITIATOR)
    private val firstPayloadMustBeEmpty: Boolean
        get() = nextMessage == 0 && pattern != NoisePattern.IK && !allowFirstMessagePayload

    /** Message 0 của XX/XXpsk3 không được mang payload (chưa mã hoá). */
    fun writeMessage(payload: ByteArray = ByteArray(0)): ByteArray {
        if (isComplete) cryptoError(CryptoErrorCode.handshakeComplete)
        if (!isMyTurnToWrite) cryptoError(CryptoErrorCode.wrongTurn)
        if (firstPayloadMustBeEmpty && payload.isNotEmpty()) cryptoError(CryptoErrorCode.invalidHandshakePayload)
        return atomically {
            val out = java.io.ByteArrayOutputStream()
            for (token in pattern.messages[nextMessage]) out.write(writeToken(token))
            out.write(symmetric.encryptAndHash(payload))
            if (out.size() > MAX_MESSAGE_LENGTH) cryptoError(CryptoErrorCode.messageTooLarge)
            finishMessage()
            out.toByteArray()
        }
    }

    fun readMessage(message: ByteArray): ByteArray {
        if (isComplete) cryptoError(CryptoErrorCode.handshakeComplete)
        if (isMyTurnToWrite) cryptoError(CryptoErrorCode.wrongTurn)
        if (message.size > MAX_MESSAGE_LENGTH) cryptoError(CryptoErrorCode.messageTooLarge)
        return atomically {
            var offset = 0
            fun take(count: Int): ByteArray {
                if (message.size - offset < count) cryptoError(CryptoErrorCode.messageTooShort)
                return message.copyOfRange(offset, offset + count).also { offset += count }
            }
            for (token in pattern.messages[nextMessage]) readToken(token, ::take)
            val payload = symmetric.decryptAndHash(message.copyOfRange(offset, message.size))
            if (firstPayloadMustBeEmpty && payload.isNotEmpty()) cryptoError(CryptoErrorCode.invalidHandshakePayload)
            finishMessage()
            payload
        }
    }

    /** Hai khoá truyền tải thô (i→r, r→i). Dùng `sessionKeys()` để ra khoá TCP/UDP. */
    fun splitKeys(): Pair<ByteArray, ByteArray> {
        if (!isComplete) cryptoError(CryptoErrorCode.handshakeIncomplete)
        return symmetric.split()
    }

    override fun toString(): String = "NoiseHandshakeState(${pattern.protocolName}, $role, message=$nextMessage)"

    private fun finishMessage() {
        nextMessage++
        if (nextMessage == 2) messageTwoHash = symmetric.hash.copyOf()
    }

    private fun <T> atomically(block: () -> T): T {
        val saved = Snapshot(symmetric.copy(), ephemeralPrivate, remoteStatic, remoteEphemeral, nextMessage, messageTwoHash)
        try {
            return block()
        } catch (e: Throwable) {
            symmetric = saved.symmetric; ephemeralPrivate = saved.ephemeral; remoteStatic = saved.remoteStatic
            remoteEphemeral = saved.remoteEphemeral; nextMessage = saved.nextMessage; messageTwoHash = saved.messageTwoHash
            throw e
        }
    }

    private class Snapshot(
        val symmetric: NoiseSymmetricState,
        val ephemeral: ByteArray?,
        val remoteStatic: ByteArray?,
        val remoteEphemeral: ByteArray?,
        val nextMessage: Int,
        val messageTwoHash: ByteArray?,
    )

    private fun writeToken(token: NoiseToken): ByteArray = when (token) {
        NoiseToken.E -> {
            val priv = ephemeralOverride ?: Primitives.randomBytes(KEY_LENGTH)
            ephemeralPrivate = priv
            Primitives.x25519PublicKey(priv).also(::mixEphemeral)
        }
        NoiseToken.S -> symmetric.encryptAndHash(staticPublicKey)
        NoiseToken.PSK -> mixPsk()
        else -> mixDiffieHellman(token)
    }

    private fun readToken(token: NoiseToken, take: (Int) -> ByteArray) {
        when (token) {
            NoiseToken.E -> {
                val bytes = take(KEY_LENGTH)
                remoteEphemeral = bytes
                mixEphemeral(bytes)
            }
            NoiseToken.S -> {
                val bytes = symmetric.decryptAndHash(take(KEY_LENGTH + if (symmetric.hasKey) Primitives.TAG_LENGTH else 0))
                if (bytes.size != KEY_LENGTH) cryptoError(CryptoErrorCode.invalidPublicKey)
                remoteStatic = bytes
            }
            NoiseToken.PSK -> mixPsk()
            else -> mixDiffieHellman(token)
        }
    }

    private fun mixEphemeral(publicBytes: ByteArray) {
        symmetric.mixHash(publicBytes)
        if (pattern.usesPresharedKey) symmetric.mixKey(publicBytes)
    }

    private fun mixPsk(): ByteArray {
        symmetric.mixKeyAndHash(psk ?: cryptoError(CryptoErrorCode.missingPresharedKey))
        return ByteArray(0)
    }

    private fun mixDiffieHellman(token: NoiseToken): ByteArray {
        val initiator = role == NoiseRole.INITIATOR
        val (priv, pub) = when (token) {
            NoiseToken.EE -> ephemeralPrivate to remoteEphemeral
            NoiseToken.ES -> if (initiator) ephemeralPrivate to remoteStatic else staticPrivateKey to remoteEphemeral
            NoiseToken.SE -> if (initiator) staticPrivateKey to remoteEphemeral else ephemeralPrivate to remoteStatic
            else -> staticPrivateKey to remoteStatic
        }
        symmetric.mixKey(Primitives.x25519(priv ?: cryptoError(CryptoErrorCode.handshakeIncomplete), pub ?: cryptoError(CryptoErrorCode.handshakeIncomplete)))
        return ByteArray(0)
    }

    companion object {
        const val MAX_MESSAGE_LENGTH = 65535
        const val KEY_LENGTH = 32
        /** Prologue cố định của wire v1 (`xdesk-wire-v1`); khác prologue thì bắt tay thất bại. */
        val DEFAULT_PROLOGUE: ByteArray = "xdesk-wire-v1".toByteArray(Charsets.US_ASCII)
    }
}
