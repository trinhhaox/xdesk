package vn.xox.xdesk.transport

import vn.xox.xdesk.crypto.CryptoErrorCode
import vn.xox.xdesk.crypto.CryptoException
import vn.xox.xdesk.crypto.DatagramFormat
import vn.xox.xdesk.crypto.DatagramReceiver
import vn.xox.xdesk.crypto.DatagramSender
import vn.xox.xdesk.wire.MediaPacket

/** Lý do một datagram bị loại. Replay/quá cũ là chuyện thường của UDP nên không tính là "bị từ chối". */
class DatagramRejection(val code: CryptoErrorCode) : Exception(code.name) {
    val countsAsRejected: Boolean get() = code != CryptoErrorCode.replayed && code != CryptoErrorCode.outsideReplayWindow
}

/** Mã hoá/giải mã [MediaPacket] cho UDP: header 16 B là AD, phần còn lại được seal. Chiều gửi cần khoá ngoài (sender không thread-safe); chiều nhận tự khoá. */
internal class UdpDatagramCipher(keys: UdpKeys) {
    private val sender = DatagramSender(keys.send)
    private val receiver = DatagramReceiver(keys.receive)
    private val receiveLock = Any()

    val sendEpoch: Long get() = sender.epoch
    val receiveEpoch: Long get() = synchronized(receiveLock) { receiver.epoch }
    val needsRekey: Boolean get() = sender.needsRekey

    fun rekey() = sender.rekey()

    fun resync(toEpoch: Long) = synchronized(receiveLock) { receiver.resync(toEpoch) }

    fun seal(packet: MediaPacket): ByteArray {
        val plain = packet.encode()
        return sender.seal(plain.copyOfRange(0, DatagramFormat.HEADER_LENGTH), plain.copyOfRange(DatagramFormat.HEADER_LENGTH, plain.size))
    }

    fun open(datagram: ByteArray): MediaPacket {
        val opened = try {
            synchronized(receiveLock) { receiver.open(datagram) }
        } catch (e: CryptoException) {
            throw DatagramRejection(e.code)
        }
        return MediaPacket.decode(opened.header + opened.payload)
    }
}
