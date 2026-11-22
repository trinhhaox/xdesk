package vn.xox.xdesk.transport

import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.UUID
import vn.xox.xdesk.wire.ControlMessage
import vn.xox.xdesk.wire.FileTransferLimits
import vn.xox.xdesk.wire.WireErrorCode
import vn.xox.xdesk.wire.WireException

enum class FileTransferDirection { SENDING, RECEIVING }

data class FileTransferProgress(
    val id: String,
    val fileName: String,
    val direction: FileTransferDirection,
    val transferredBytes: Long,
    val totalBytes: Long,
) {
    val fraction: Float
        get() = if (totalBytes <= 0L) 1f else (transferredBytes.toDouble() / totalBytes.toDouble()).toFloat().coerceIn(0f, 1f)
}

data class FileTransferCompletion(
    val id: String,
    val fileName: String,
    val file: File,
    val size: Long,
)

object FileTransferNaming {
    fun sanitizedName(raw: String): String {
        val last = raw.replace('\\', '/').split('/').lastOrNull { it.isNotEmpty() }?.trim().orEmpty()
        return if (last.isEmpty() || last == "." || last == "..") "file" else last
    }

    fun uniqueName(preferredName: String, exists: (String) -> Boolean): String {
        val clean = sanitizedName(preferredName)
        if (!exists(clean)) return clean
        val dot = clean.lastIndexOf('.')
        val hasExt = dot > 0 && dot < clean.length - 1
        val stem = if (hasExt) clean.substring(0, dot) else clean
        val ext = if (hasExt) clean.substring(dot + 1) else ""
        for (i in 1..10_000) {
            val candidate = if (ext.isEmpty()) "$stem ($i)" else "$stem ($i).$ext"
            if (!exists(candidate)) return candidate
        }
        return "${UUID.randomUUID()}-$clean"
    }

    fun sha256Hex(bytes: ByteArray): String {
        val hex = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            val v = b.toInt() and 0xFF
            hex.append(HEX_CHARS[v ushr 4])
            hex.append(HEX_CHARS[v and 0x0F])
        }
        return hex.toString()
    }

    private val HEX_CHARS = "0123456789abcdef".toCharArray()
}

/** Bộ nhận tệp streaming qua `file.start` -> `[file.chunk, BULK]` -> `file.done` (ghi thẳng ra tệp tạm, xác minh SHA-256). */
class FileTransferReceiver(
    private val tempDirectory: File,
    private val onProgress: (FileTransferProgress?) -> Unit = {},
    private val onCompleted: (FileTransferCompletion) -> Unit = {},
    private val onFailed: (String, String) -> Unit = { _, _ -> },
) {
    private class Active(
        val id: String,
        val fileName: String,
        val totalBytes: Long,
        val partFile: File,
        val output: FileOutputStream,
        val digest: MessageDigest,
        var receivedBytes: Long = 0L,
    )

    private val lock = Any()
    private val transfers = HashMap<String, Active>()
    private var pendingBulk: Pair<String, Int>? = null

    fun handleStart(start: ControlMessage.FileStart) {
        val name = FileTransferNaming.sanitizedName(start.name)
        if (start.size < 0L || start.size > FileTransferLimits.MAX_BYTES) {
            onFailed(name, "Tệp vượt quá giới hạn 2 GB")
            return
        }
        val active = synchronized(lock) {
            transfers.remove(start.id)?.let { old ->
                runCatching { old.output.close() }
                old.partFile.delete()
            }
            tempDirectory.mkdirs()
            val part = File(tempDirectory, ".xdesk-${UUID.randomUUID()}.part")
            val stream = try {
                FileOutputStream(part)
            } catch (e: Exception) {
                part.delete()
                null
            }
            if (stream == null) return@synchronized null
            val created = Active(
                id = start.id,
                fileName = name,
                totalBytes = start.size,
                partFile = part,
                output = stream,
                digest = MessageDigest.getInstance("SHA-256"),
            )
            transfers[start.id] = created
            created
        }
        if (active == null) {
            onFailed(name, "Không tạo được tệp tạm")
            return
        }
        onProgress(FileTransferProgress(start.id, name, FileTransferDirection.RECEIVING, 0L, start.size))
    }

    fun handleChunkHeader(chunk: ControlMessage.FileChunk) {
        synchronized(lock) {
            pendingBulk = if (transfers.containsKey(chunk.id)) chunk.id to chunk.size.toInt() else null
        }
    }

    /** Nạp 1 frame `BULK` nếu trước đó vừa nhận `file.chunk`. Trả `true` nếu đã tiêu thụ cho file transfer. */
    fun handleBulk(bytes: ByteArray): Boolean {
        val pending = synchronized(lock) { pendingBulk.also { pendingBulk = null } } ?: return false
        val (id, expectedSize) = pending
        var errorMessage: String? = null
        var failedName = "file"
        var progressUpdate: FileTransferProgress? = null
        synchronized(lock) {
            val active = transfers[id] ?: return true
            failedName = active.fileName
            if (bytes.size != expectedSize || active.receivedBytes + bytes.size > active.totalBytes) {
                transfers.remove(id)
                runCatching { active.output.close() }
                active.partFile.delete()
                errorMessage = "Dữ liệu tệp không khớp kích thước"
            } else {
                try {
                    active.output.write(bytes)
                    active.digest.update(bytes)
                    active.receivedBytes += bytes.size
                    progressUpdate = FileTransferProgress(
                        active.id, active.fileName, FileTransferDirection.RECEIVING, active.receivedBytes, active.totalBytes,
                    )
                } catch (e: Exception) {
                    transfers.remove(id)
                    runCatching { active.output.close() }
                    active.partFile.delete()
                    errorMessage = e.message ?: "Lỗi ghi tệp"
                }
            }
        }
        if (errorMessage != null) {
            onProgress(null)
            onFailed(failedName, errorMessage!!)
        } else if (progressUpdate != null) {
            onProgress(progressUpdate)
        }
        return true
    }

    fun handleDone(done: ControlMessage.FileDone) {
        var completion: FileTransferCompletion? = null
        var failed: Pair<String, String>? = null
        synchronized(lock) {
            if (pendingBulk?.first == done.id) pendingBulk = null
            val active = transfers.remove(done.id) ?: return
            runCatching { active.output.close() }
            val actualHash = FileTransferNaming.sha256Hex(active.digest.digest())
            if (active.receivedBytes != active.totalBytes || actualHash != done.hash) {
                active.partFile.delete()
                failed = active.fileName to "Tệp bị hỏng hoặc thiếu dữ liệu (sai SHA-256)"
            } else {
                val readyFile = File(tempDirectory, "${active.partFile.nameWithoutExtension}.ready")
                val finalFile = if (active.partFile.renameTo(readyFile)) readyFile else active.partFile
                completion = FileTransferCompletion(active.id, active.fileName, finalFile, active.totalBytes)
            }
        }
        onProgress(null)
        completion?.let(onCompleted)
        failed?.let { onFailed(it.first, it.second) }
    }

    fun handleCancel(cancel: ControlMessage.FileCancel) {
        val removed = synchronized(lock) {
            if (pendingBulk?.first == cancel.id) pendingBulk = null
            transfers.remove(cancel.id)?.also {
                runCatching { it.output.close() }
                it.partFile.delete()
            }
        }
        if (removed != null) onProgress(null)
    }

    fun cancelAll() {
        val hadAny = synchronized(lock) {
            pendingBulk = null
            val empty = transfers.isEmpty()
            for (active in transfers.values) {
                runCatching { active.output.close() }
                active.partFile.delete()
            }
            transfers.clear()
            !empty
        }
        if (hadAny) onProgress(null)
    }
}

object FileTransferSender {
    fun sendFile(
        id: String = UUID.randomUUID().toString(),
        fileName: String,
        totalBytes: Long,
        input: InputStream,
        connection: ControlConnection,
        isCancelled: () -> Boolean = { false },
        onProgress: (FileTransferProgress?) -> Unit = {},
    ): Boolean {
        if (totalBytes < 0L || totalBytes > FileTransferLimits.MAX_BYTES) {
            throw WireException(WireErrorCode.invalidField, "file.start.size")
        }
        val cleanName = FileTransferNaming.sanitizedName(fileName)
        connection.send(ControlMessage.FileStart(id, cleanName, totalBytes))
        onProgress(FileTransferProgress(id, cleanName, FileTransferDirection.SENDING, 0L, totalBytes))

        val buffer = ByteArray(FileTransferLimits.CHUNK_BYTES)
        val digest = MessageDigest.getInstance("SHA-256")
        var sentBytes = 0L
        while (true) {
            if (isCancelled()) {
                runCatching { connection.send(ControlMessage.FileCancel(id, "cancelled")) }
                onProgress(null)
                return false
            }
            val n = readFullChunk(input, buffer)
            if (n <= 0) break
            val payload = if (n == buffer.size) buffer.copyOf() else buffer.copyOf(n)
            digest.update(payload)
            connection.sendFileBulkChunk(ControlMessage.FileChunk(id, n.toLong()), payload)
            sentBytes += n
            onProgress(FileTransferProgress(id, cleanName, FileTransferDirection.SENDING, sentBytes, totalBytes))
        }
        val hash = FileTransferNaming.sha256Hex(digest.digest())
        connection.send(ControlMessage.FileDone(id, hash))
        onProgress(null)
        return true
    }

    private fun readFullChunk(input: InputStream, buffer: ByteArray): Int {
        var total = 0
        while (total < buffer.size) {
            val read = input.read(buffer, total, buffer.size - total)
            if (read < 0) break
            total += read
        }
        return total
    }
}
