package vn.xox.xdesk.transport

import java.io.File
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.Base64
import vn.xox.xdesk.crypto.DeviceFingerprint

/** Host đã ghép. `id` = fingerprint của `publicKey`; `lastAddress` dạng `host:port` (dùng khi nhập tay). */
class KnownHost(
    val id: String,
    val name: String,
    val publicKey: ByteArray,
    val lastAddress: String? = null,
    val addedMs: Long = 0,
    val lastSeenMs: Long = 0,
)

/** Nơi lưu host đã biết; bản Android có thể thay bằng lưu trong bộ nhớ riêng của app. Mọi thao tác đồng bộ, thread-safe. */
interface KnownHostStore {
    fun all(): List<KnownHost>
    fun add(name: String, publicKey: ByteArray, nowMs: Long): KnownHost
    fun remove(id: String): Boolean
    fun markSeen(id: String, nowMs: Long)
    fun setLastAddress(id: String, address: String)
}

/**
 * Lưu danh sách trong một file văn bản (mỗi host một dòng, trường mã hoá base64url), ghi nguyên tử (tạo file tạm rồi move).
 * File hỏng bị đổi tên thành `.corrupt` (không bao giờ xoá) và danh sách bắt đầu rỗng; [recoveredFromCorruption] báo cho UI.
 */
class FileKnownHostStore(private val file: File) : KnownHostStore {
    private val hosts = LinkedHashMap<String, KnownHost>()

    /** `true` nếu lần mở này phải cách ly một file hỏng. */
    var recoveredFromCorruption = false
        private set

    init {
        if (file.exists()) {
            try {
                file.readLines(StandardCharsets.UTF_8).forEachIndexed { index, line ->
                    if (index == 0) require(line == HEADER) else if (line.isNotEmpty()) parse(line).let { hosts[it.id] = it }
                }
            } catch (e: IllegalArgumentException) {
                quarantine()
            } catch (e: IndexOutOfBoundsException) {
                quarantine()
            }
        }
    }

    @Synchronized override fun all(): List<KnownHost> = hosts.values.toList()

    @Synchronized override fun add(name: String, publicKey: ByteArray, nowMs: Long): KnownHost {
        val id = DeviceFingerprint.make(publicKey)
        val host = KnownHost(id, name, publicKey.copyOf(), hosts[id]?.lastAddress, hosts[id]?.addedMs ?: nowMs, nowMs)
        hosts[id] = host
        persist()
        return host
    }

    @Synchronized override fun remove(id: String): Boolean = (hosts.remove(id) != null).also { if (it) persist() }

    @Synchronized override fun markSeen(id: String, nowMs: Long) = update(id) { KnownHost(it.id, it.name, it.publicKey, it.lastAddress, it.addedMs, nowMs) }

    /** Một địa chỉ chỉ thuộc một host: Mac khác từng giữ địa chỉ này (DHCP cấp lại) bị bỏ địa chỉ để `device(address)` không trả nhầm khoá. */
    @Synchronized override fun setLastAddress(id: String, address: String) {
        if (id !in hosts) return
        hosts.replaceAll { key, host ->
            when {
                key == id -> KnownHost(host.id, host.name, host.publicKey, address, host.addedMs, host.lastSeenMs)
                host.lastAddress == address -> KnownHost(host.id, host.name, host.publicKey, null, host.addedMs, host.lastSeenMs)
                else -> host
            }
        }
        persist()
    }

    private fun update(id: String, change: (KnownHost) -> KnownHost) {
        val current = hosts[id] ?: return
        hosts[id] = change(current)
        persist()
    }

    private fun quarantine() {
        hosts.clear()
        recoveredFromCorruption = true
        Files.move(file.toPath(), File(file.path + ".corrupt").toPath(), StandardCopyOption.REPLACE_EXISTING)
    }

    private fun persist() {
        val text = (listOf(HEADER) + hosts.values.map(::encode)).joinToString("\n", postfix = "\n")
        val temp = File(file.path + ".tmp")
        try {
            file.parentFile?.mkdirs()
            temp.writeText(text, StandardCharsets.UTF_8)
            Files.move(temp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } catch (e: IOException) {
            throw IOException("Không lưu được danh sách host đã ghép", e)
        }
    }

    private fun encode(h: KnownHost): String = listOf(
        h.id, b64(h.name.toByteArray(Charsets.UTF_8)), b64(h.publicKey), b64((h.lastAddress ?: "").toByteArray(Charsets.UTF_8)),
        h.addedMs.toString(), h.lastSeenMs.toString(),
    ).joinToString("\t")

    private fun parse(line: String): KnownHost {
        val f = line.split('\t')
        require(f.size == 6)
        val key = Base64.getUrlDecoder().decode(f[2])
        require(key.size == 32 && DeviceFingerprint.make(key) == f[0])
        val address = String(Base64.getUrlDecoder().decode(f[3]), Charsets.UTF_8)
        return KnownHost(
            f[0], String(Base64.getUrlDecoder().decode(f[1]), Charsets.UTF_8), key, address.ifEmpty { null },
            f[4].toLong(), f[5].toLong(),
        )
    }

    private fun b64(bytes: ByteArray) = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

    private companion object { const val HEADER = "xdesk-known-hosts v1" }
}
