import Foundation

/// Decoder phần cứng Unisoc/MediaTek chỉ xuất khung N khi nhận khung N+1, nên khi màn hình đứng yên (ScreenCaptureKit
/// không phát khung) khung cuối kẹt trong decoder. Sau mỗi khung thật, nếu `delay` trôi qua mà chưa có khung mới thì gọi
/// `repeatLast` đúng một lần (host mã hoá lại khung cuối → P-frame gần như rỗng, vài chục byte) để đẩy khung kẹt ra.
/// An toàn đa luồng; `repeatLast` chạy trên hàng đợi nội bộ.
public final class IdleFrameRepeater: @unchecked Sendable {
    private let delay: DispatchTimeInterval
    private let queue = DispatchQueue(label: "vn.xox.xdesk.idle-frame-repeater")
    private let repeatLast: @Sendable () -> Void
    private let lock = NSLock()
    private var pending: DispatchWorkItem?

    public init(delay: DispatchTimeInterval = .milliseconds(50), repeatLast: @escaping @Sendable () -> Void) {
        self.delay = delay
        self.repeatLast = repeatLast
    }

    /// Gọi sau mỗi khung thật đã mã hoá: huỷ hẹn cũ, hẹn lại.
    public func frameEncoded() {
        let item = DispatchWorkItem { [repeatLast] in repeatLast() }
        lock.withLock {
            pending?.cancel()
            pending = item
        }
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    public func cancel() {
        lock.withLock {
            pending?.cancel()
            pending = nil
        }
    }
}
