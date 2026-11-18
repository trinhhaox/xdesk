import Foundation

/// Số liệu thu theo cửa sổ 500 ms cho `net.report`: mất khung (khoảng trống frameNo), băng thông nhận, fps hiển thị.
struct ViewerStats {
    struct Window {
        let lossPermille: Int
        let recvKbps: Int
        let fps: Int
    }

    private var windowStartMs = 0
    private var bytes = 0
    private var frames = 0
    private var firstFrameNo: UInt32?
    private var highestFrameNo: UInt32 = 0

    mutating func record(frameNo: UInt32, byteCount: Int) {
        bytes += byteCount
        frames += 1
        if firstFrameNo == nil { firstFrameNo = frameNo }
        highestFrameNo = max(highestFrameNo, frameNo)
    }

    /// Đóng cửa sổ nếu đã đủ `intervalMs`; trả số liệu và mở cửa sổ mới.
    mutating func closeWindow(nowMs: Int, intervalMs: Int = 500) -> Window? {
        guard nowMs - windowStartMs >= intervalMs else { return nil }
        let elapsed = max(1, nowMs - windowStartMs)
        let expected = firstFrameNo.map { max(0, Int(highestFrameNo) - Int($0) + 1) } ?? 0
        let lost = max(0, expected - frames)
        let loss = expected > 0 ? lost * 1000 / expected : 0
        let result = Window(lossPermille: loss, recvKbps: bytes * 8 / elapsed, fps: frames * 1000 / elapsed)
        windowStartMs = nowMs
        bytes = 0
        frames = 0
        firstFrameNo = highestFrameNo &+ 1
        return result
    }
}
