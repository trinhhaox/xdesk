package vn.xox.xdesk.crypto

/** CipherState của Noise (rev 34 §5.1): khoá tuỳ chọn + bộ đếm nonce 64-bit (so sánh `-1L` = UInt64.max). */
internal class NoiseCipherState(var key: ByteArray? = null) {
    var nonce = 0L
        private set

    val hasKey: Boolean get() = key != null

    fun initializeKey(newKey: ByteArray?) { key = newKey; nonce = 0 }

    fun copy() = NoiseCipherState(key).also { it.nonce = nonce }

    fun encrypt(ad: ByteArray, plaintext: ByteArray): ByteArray {
        val k = key ?: return plaintext
        if (nonce == -1L) cryptoError(CryptoErrorCode.nonceExhausted)
        return Primitives.seal(k, nonce, ad, plaintext).also { nonce++ }
    }

    fun decrypt(ad: ByteArray, ciphertext: ByteArray): ByteArray {
        val k = key ?: return ciphertext
        if (nonce == -1L) cryptoError(CryptoErrorCode.nonceExhausted)
        return Primitives.open(k, nonce, ad, ciphertext).also { nonce++ }
    }
}

/** SymmetricState của Noise (rev 34 §5.2) với HASH = SHA-256. */
internal class NoiseSymmetricState private constructor(
    private var chainingKey: ByteArray,
    var hash: ByteArray,
    private val cipher: NoiseCipherState,
) {
    constructor(protocolName: String) : this(ByteArray(0), ByteArray(0), NoiseCipherState()) {
        val name = protocolName.toByteArray(Charsets.US_ASCII)
        hash = if (name.size <= 32) name.copyOf(32) else Primitives.sha256(name)
        chainingKey = hash
    }

    val hasKey: Boolean get() = cipher.hasKey

    fun copy() = NoiseSymmetricState(chainingKey, hash, cipher.copy())

    fun mixHash(data: ByteArray) { hash = Primitives.sha256(hash, data) }

    fun mixKey(ikm: ByteArray) {
        val out = Primitives.noiseHkdf(chainingKey, ikm, 2)
        chainingKey = out[0]
        cipher.initializeKey(out[1])
    }

    fun mixKeyAndHash(ikm: ByteArray) {
        val out = Primitives.noiseHkdf(chainingKey, ikm, 3)
        chainingKey = out[0]
        mixHash(out[1])
        cipher.initializeKey(out[2])
    }

    fun encryptAndHash(plaintext: ByteArray): ByteArray =
        cipher.encrypt(hash, plaintext).also { mixHash(it) }

    fun decryptAndHash(ciphertext: ByteArray): ByteArray =
        cipher.decrypt(hash, ciphertext).also { mixHash(ciphertext) }

    /** Hai khoá truyền tải thô: (initiator → responder, responder → initiator). */
    fun split(): Pair<ByteArray, ByteArray> {
        val out = Primitives.noiseHkdf(chainingKey, ByteArray(0), 2)
        return out[0] to out[1]
    }
}
