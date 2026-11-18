import Foundation
import Network

/// Cổng "chỉ một lần" để resume continuation đúng một lần từ nhiều callback.
final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// `true` cho người gọi đầu tiên.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Mốc thời gian đơn điệu (ms) cho NACK/ABR; không phụ thuộc đồng hồ hệ thống.
func monotonicMs() -> Int { Int(DispatchTime.now().uptimeNanoseconds / 1_000_000) }

/// Khởi động `NWConnection` và chờ `ready`; lỗi/huỷ/quá hạn → ném `TransportError`.
func startAndAwaitReady(_ connection: NWConnection, queue: DispatchQueue, timeoutSeconds: Double = 5) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
        let gate = ResumeGate()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if gate.claim() { cont.resume() }
            case .failed(let error):
                if gate.claim() { cont.resume(throwing: TransportError.connectionFailed("\(error)")) }
            case .cancelled:
                if gate.claim() { cont.resume(throwing: TransportError.connectionClosed) }
            default:
                break
            }
        }
        queue.asyncAfter(deadline: .now() + timeoutSeconds) {
            if gate.claim() {
                cont.resume(throwing: TransportError.timedOut)
                connection.cancel()
            }
        }
        connection.start(queue: queue)
    }
}

/// Chờ `NWListener` ready và trả cổng thực.
func startAndAwaitPort(_ listener: NWListener, queue: DispatchQueue, timeoutSeconds: Double = 5) async throws -> UInt16 {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, any Error>) in
        let gate = ResumeGate()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard gate.claim() else { return }
                if let port = listener.port?.rawValue {
                    cont.resume(returning: port)
                } else {
                    cont.resume(throwing: TransportError.listenerFailed("no port"))
                }
            case .failed(let error):
                if gate.claim() { cont.resume(throwing: TransportError.listenerFailed("\(error)")) }
            case .cancelled:
                if gate.claim() { cont.resume(throwing: TransportError.connectionClosed) }
            default:
                break
            }
        }
        queue.asyncAfter(deadline: .now() + timeoutSeconds) {
            if gate.claim() {
                cont.resume(throwing: TransportError.timedOut)
                listener.cancel()
            }
        }
        listener.start(queue: queue)
    }
}
