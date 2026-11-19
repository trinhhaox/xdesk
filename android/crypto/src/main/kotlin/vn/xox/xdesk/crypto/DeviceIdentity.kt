package vn.xox.xdesk.crypto

/** Danh tính thiết bị: khoá tĩnh X25519 (32 B, không rời thiết bị) + dấu vân tay hiển thị. */
class DeviceIdentity(privateKey: ByteArray) {
    private val privateKeyBytes = privateKey.copyOf()
    val publicKey: ByteArray = Primitives.x25519PublicKey(privateKeyBytes)
    val fingerprint: String get() = DeviceFingerprint.make(publicKey)

    /** Bản sao khoá riêng để đưa vào `NoiseHandshakeState`; không log. */
    fun privateKey(): ByteArray = privateKeyBytes.copyOf()

    override fun toString(): String = "DeviceIdentity($fingerprint)"

    companion object {
        fun generate() = DeviceIdentity(Primitives.randomBytes(32))
    }
}

object DeviceFingerprint {
    /** 8 byte đầu của SHA-256(pub), hex HOA, nhóm 4 ký tự nối bằng `-`: `AB12-CD34-EF56-7890`. */
    fun make(publicKey: ByteArray): String =
        Primitives.sha256(publicKey).take(8).joinToString("") { "%02X".format(it) }.chunked(4).joinToString("-")
}

/** Nơi lưu danh tính. Bản Android Keystore nằm ở phase 07b; ở đây chỉ có giao diện và bản trong bộ nhớ. */
interface IdentityStore {
    /** Trả khoá đã lưu, hoặc tạo khoá mới và lưu lần đầu. */
    fun loadOrCreate(): DeviceIdentity

    /** Xoá khoá (đặt lại danh tính); lần `loadOrCreate` sau tạo khoá mới. */
    fun delete()
}

class InMemoryIdentityStore(private var identity: DeviceIdentity? = null) : IdentityStore {
    @Synchronized
    override fun loadOrCreate(): DeviceIdentity = identity ?: DeviceIdentity.generate().also { identity = it }

    @Synchronized
    override fun delete() { identity = null }
}
