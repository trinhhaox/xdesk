import Foundation

/// Mã 6 số phía viewer. UI hiện `code` rồi gọi `answer(_:)` khi người dùng so với mã trên host.
///
/// Ghép đôi SAS chỉ an toàn khi cả hai phía cùng xác nhận: host bấm "Khớp" chưa đủ, vì một máy
/// mạo danh host trên LAN có thể tự trả `pair.result{accepted:true}`. Viewer chỉ lưu host sau khi
/// chính người dùng ở viewer bấm "Khớp".
public final class SasPrompt: @unchecked Sendable {
    public let code: String

    private let lock = NSLock()
    private var result: Bool?
    private var waiter: CheckedContinuation<Bool, Never>?
    private let onMismatch: @Sendable () -> Void

    init(code: String, onMismatch: @escaping @Sendable () -> Void = {}) {
        self.code = code
        self.onMismatch = onMismatch
    }

    /// `true` = mã khớp với host; `false` = không khớp (huỷ ghép đôi ngay). Chỉ lần trả lời đầu có hiệu lực.
    public func answer(_ matched: Bool) {
        guard resolve(matched), !matched else { return }
        onMismatch()
    }

    /// Câu trả lời đã có (nil = chưa trả lời).
    var answered: Bool? { lock.withLock { result } }

    /// Còn chờ người dùng trả lời. UI chỉ hiện prompt còn chờ: ghép đôi đã kết thúc (host từ chối, mất kết nối)
    /// thì prompt đã bị bỏ và không được hiện lại.
    public var isPending: Bool { answered == nil }

    /// Kết nối đóng giữa chừng (huỷ, lỗi): coi như không khớp, không gọi lại hook đóng kết nối.
    func abandon() { resolve(false) }

    /// Chờ người dùng trả lời; quá hạn hoặc task bị huỷ thì coi là không khớp.
    func decision(timeoutSeconds: Double) async -> Bool {
        let timer = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                self?.resolve(false)
            } catch {
                // Bị huỷ vì đã có câu trả lời: không làm gì.
            }
        }
        defer { timer.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let ready: Bool? = lock.withLock {
                    if let result { return result }
                    waiter = continuation
                    return nil
                }
                if let ready { continuation.resume(returning: ready) }
            }
        } onCancel: {
            resolve(false)
        }
    }

    /// Ghi câu trả lời đầu tiên và đánh thức người đang chờ. Trả `false` nếu đã có câu trả lời trước đó.
    @discardableResult
    private func resolve(_ matched: Bool) -> Bool {
        let (accepted, pending): (Bool, CheckedContinuation<Bool, Never>?) = lock.withLock {
            guard result == nil else { return (false, nil) }
            result = matched
            defer { waiter = nil }
            return (true, waiter)
        }
        pending?.resume(returning: matched)
        return accepted
    }
}
