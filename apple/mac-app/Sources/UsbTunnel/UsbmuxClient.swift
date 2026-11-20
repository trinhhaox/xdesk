import Foundation
import Network

/// Nói chuyện với usbmuxd qua socket Unix `/var/run/usbmuxd` bằng giao thức plist; không thư viện ngoài.
/// `listen` báo cắm/rút; `connect` biến socket thành đường hầm TCP thô tới một cổng trên thiết bị (sau `Result 0`, mọi byte đi thẳng).
struct UsbmuxClient: Sendable {
    static let defaultPath = "/var/run/usbmuxd"
    private static let responseTimeoutSeconds = 5.0

    let path: String

    init(path: String = UsbmuxClient.defaultPath) { self.path = path }

    // MARK: Listen

    /// Luồng sự kiện cắm/rút (thiết bị đang cắm được báo ngay sau khi nghe). Luồng kết thúc có lỗi khi usbmuxd đóng socket.
    func listen() -> AsyncThrowingStream<UsbmuxEvent, any Error> {
        AsyncThrowingStream { continuation in
            let holder = SocketHolder()
            let task = Task {
                do {
                    let socket = try await UsbmuxSocket.open(path: path)
                    holder.set(socket)
                    try await socket.send(UsbmuxPlist.listenRequest(tag: 1))
                    let first = try await socket.receiveMessage(timeoutSeconds: Self.responseTimeoutSeconds)
                    guard case .result(let result) = first else { throw UsbmuxError.malformedPlist("cần Result sau Listen") }
                    guard result.isOK else { throw UsbmuxError.refused(result) }
                    continuation.yield(.listening)
                    while true {
                        if case .event(let event) = try await socket.receiveMessage(timeoutSeconds: nil) { continuation.yield(event) }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                holder.cancel()
            }
        }
    }

    // MARK: Connect

    /// Mở đường hầm TCP tới `port` trên thiết bị. Kết nối trả về đã `ready` và là TCP thô tới app trên iPhone/iPad.
    func connect(deviceID: Int, port: UInt16) async throws -> NWConnection {
        let socket = try await UsbmuxSocket.open(path: path)
        do {
            try await socket.send(UsbmuxPlist.connectRequest(deviceID: deviceID, port: port, tag: 1))
            guard case .result(let result) = try await socket.receiveMessage(timeoutSeconds: Self.responseTimeoutSeconds) else {
                throw UsbmuxError.malformedPlist("cần Result sau Connect")
            }
            guard result.isOK else { throw UsbmuxError.refused(result) }
            return socket.connection
        } catch {
            socket.cancel()
            throw error
        }
    }
}

/// Một kết nối tới usbmuxd: đọc đúng từng khung (không đọc lố sang byte của đường hầm).
final class UsbmuxSocket: @unchecked Sendable {
    let connection: NWConnection
    private let queue = DispatchQueue(label: "xdesk.usbmux")

    private init(_ connection: NWConnection) { self.connection = connection }

    static func open(path: String) async throws -> UsbmuxSocket {
        guard FileManager.default.fileExists(atPath: path) else { throw UsbmuxError.unavailable(String(localized: "không có \(path)")) }
        let socket = UsbmuxSocket(NWConnection(to: .unix(path: path), using: .tcp))
        try await socket.waitReady()
        return socket
    }

    func cancel() { connection.cancel() }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: UsbmuxError.unavailable("\(error)")) } else { cont.resume() }
            })
        }
    }

    func receiveMessage(timeoutSeconds: Double?) async throws -> UsbmuxMessage {
        let header = try await readExactly(UsbmuxPlist.headerSize, timeoutSeconds: timeoutSeconds)
        let (length, _) = try UsbmuxPlist.parseHeader(header)
        let payload = length == 0 ? Data() : try await readExactly(length, timeoutSeconds: Self.payloadTimeoutSeconds)
        return try UsbmuxPlist.parseMessage(payload)
    }

    private static let payloadTimeoutSeconds = 5.0

    private func readExactly(_ count: Int, timeoutSeconds: Double?) async throws -> Data {
        let gate = Gate()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, any Error>) in
            if let timeoutSeconds {
                queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                    if gate.claim() { cont.resume(throwing: UsbmuxError.unavailable(String(localized: "usbmuxd không trả lời"))); self.connection.cancel() }
                }
            }
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                guard gate.claim() else { return }
                if let error { cont.resume(throwing: UsbmuxError.unavailable("\(error)")) }
                else if let data, data.count == count { cont.resume(returning: data) }
                else { cont.resume(throwing: UsbmuxError.unavailable(String(localized: "usbmuxd đóng socket"))) }
            }
        }
    }

    private func waitReady() async throws {
        let gate = Gate()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if gate.claim() { cont.resume() }
                case .failed(let error): if gate.claim() { cont.resume(throwing: UsbmuxError.unavailable("\(error)")) }
                case .cancelled: if gate.claim() { cont.resume(throwing: UsbmuxError.unavailable(String(localized: "đã huỷ"))) }
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + 5) {
                if gate.claim() { cont.resume(throwing: UsbmuxError.unavailable(String(localized: "quá hạn nối socket"))); self.connection.cancel() }
            }
            connection.start(queue: queue)
        }
        connection.stateUpdateHandler = nil
    }
}

/// Cho phép resume continuation đúng một lần từ nhiều callback.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Giữ socket của một phiên `listen` để huỷ được khi luồng bị bỏ.
private final class SocketHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var socket: UsbmuxSocket?
    private var cancelled = false

    func set(_ socket: UsbmuxSocket) {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { socket.cancel() } else { self.socket = socket }
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        socket?.cancel()
    }
}
