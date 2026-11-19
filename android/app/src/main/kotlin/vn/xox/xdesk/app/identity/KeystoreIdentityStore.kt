package vn.xox.xdesk.app.identity

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import vn.xox.xdesk.crypto.DeviceIdentity
import vn.xox.xdesk.crypto.IdentityStore

/**
 * Danh tính thiết bị: khoá tĩnh X25519 được bọc bằng khoá AES-GCM 256 bit trong Android Keystore (không xuất được);
 * bản bọc nằm trong bộ nhớ riêng của app (`allowBackup=false`, nên không theo bản sao lưu sang máy khác).
 * Không bao giờ ghi khoá thô ra đĩa hay log. Nếu Keystore mất khoá, [loadOrCreate] ném [IdentityUnavailableException]
 * thay vì lặng lẽ tạo danh tính mới; người dùng quyết định gọi [delete] để đặt lại.
 */
class KeystoreIdentityStore(private val file: File, private val alias: String = DEFAULT_ALIAS) : IdentityStore {
    @Synchronized
    override fun loadOrCreate(): DeviceIdentity {
        if (file.exists()) {
            val secret = WrappedKeyCodec.unwrap(wrappingKey(create = false), file.readBytes())
            return try { DeviceIdentity(secret) } finally { secret.fill(0) }
        }
        val identity = DeviceIdentity.generate()
        val secret = identity.privateKey()
        try {
            val temp = File(file.path + ".tmp")
            temp.writeBytes(WrappedKeyCodec.wrap(wrappingKey(create = true), secret))
            Files.move(temp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } finally {
            secret.fill(0)
        }
        return identity
    }

    @Synchronized
    override fun delete() {
        file.delete()
        keyStore().deleteEntry(alias)
    }

    private fun keyStore() = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun wrappingKey(create: Boolean): SecretKey {
        val store = keyStore()
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        if (!create) throw IdentityUnavailableException(IllegalStateException("khoá Keystore đã mất"))
        val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE).apply { init(spec) }.generateKey()
    }

    companion object {
        const val DEFAULT_ALIAS = "xdesk.identity.wrap"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    }
}
