package vn.xox.xdesk.crypto

/** Chẩn đoán công khai cho log khởi động của app (module :crypto giữ [Primitives] ở mức internal). */
object CryptoDiagnostics {
    /** Một dòng, không chứa khoá: đường X25519 và cipher AEAD đang dùng. */
    fun describe(): String = Primitives.describePaths()
}
