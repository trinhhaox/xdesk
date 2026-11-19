package vn.xox.xdesk.transport

/** Bộ đếm của [UdpMediaChannel] (chỉ để đo/hiển thị; không bao giờ làm đóng kênh). */
class UdpChannelStats {
    @Volatile var datagramsReceived = 0L
        internal set

    /** Datagram bị loại vì tag/epoch/độ dài sai (chưa xác thực). */
    @Volatile var rejectedDatagramCount = 0L
        internal set

    @Volatile var malformedPacketCount = 0L
        internal set

    @Volatile var framesAssembled = 0L
        internal set
}
