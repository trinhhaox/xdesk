import Foundation
import os

/// Tự `adb reverse` cổng điều khiển cho điện thoại Android cắm cáp (đã bật USB debugging),
/// để app Android nối `127.0.0.1:47800` qua cáp. Không có adb trên máy thì không làm gì.
actor AdbReverseWatcher {
    static let pollInterval: Duration = .seconds(4)

    private let adbPath: String?
    private var task: Task<Void, Never>?
    /// Serial đã reverse thành công trong lần cắm hiện tại; rút cáp thì xoá để lần cắm sau làm lại.
    private var reversed: Set<String> = []
    /// Tăng mỗi lần start/stop để vòng `tick` cũ (đang chờ adb) không ghi đè trạng thái mới.
    private var generation = 0
    private var activePublicPort: UInt16?
    private let log = Logger(subsystem: "vn.xox.xdesk", category: "adb-reverse")

    init(adbPath: String? = AdbReverseWatcher.locateAdb()) { self.adbPath = adbPath }

    /// Đường dẫn adb thường gặp trên Mac (Homebrew, Android Studio, SDK trên ổ ngoài, biến môi trường).
    static func locateAdb(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        var candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb",
            "/Volumes/XcodeExternal/Android/sdk/platform-tools/adb",
        ]
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = environment[key] { candidates.insert(root + "/platform-tools/adb", at: 0) }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Lấy serial các máy ở trạng thái `device` từ kết quả `adb devices` (bỏ `unauthorized`/`offline`).
    static func parseDevices(_ output: String) -> Set<String> {
        var serials: Set<String> = []
        for line in output.split(whereSeparator: \.isNewline).dropFirst() {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count >= 2, parts[1] == "device" { serials.insert(String(parts[0])) }
        }
        return serials
    }

    /// `publicPort`: cổng app Android gọi trên 127.0.0.1; `hostPort`: cổng listener thật (có thể khác nếu 47800 bận).
    func start(publicPort: UInt16, hostPort: UInt16) {
        guard task == nil, let adb = adbPath else { return }
        generation &+= 1
        let gen = generation
        reversed = []
        activePublicPort = publicPort
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick(adb: adb, publicPort: publicPort, hostPort: hostPort, gen: gen)
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    /// Dừng theo dõi và gỡ mapping đã đặt (chạy nền, không chặn), để cổng điện thoại không còn trỏ về Mac khi thôi chia sẻ.
    func stop() {
        task?.cancel()
        task = nil
        generation &+= 1
        let serials = reversed
        reversed = []
        guard let adb = adbPath, let port = activePublicPort, !serials.isEmpty else { return }
        activePublicPort = nil
        Task.detached {
            for serial in serials { _ = await Self.run(adb, ["-s", serial, "reverse", "--remove", "tcp:\(port)"]) }
        }
    }

    private func tick(adb: String, publicPort: UInt16, hostPort: UInt16, gen: Int) async {
        guard let output = await Self.run(adb, ["devices"]), gen == generation else { return }
        let present = Self.parseDevices(output.text)
        reversed.formIntersection(present)
        for serial in present.subtracting(reversed) {
            // Có thể đã stop/start lại trong lúc chờ adb (actor reentrancy): bỏ, không ghi trạng thái cũ.
            guard gen == generation, !Task.isCancelled else { return }
            let args = ["-s", serial, "reverse", "tcp:\(publicPort)", "tcp:\(hostPort)"]
            let result = await Self.run(adb, args)
            guard gen == generation else { return }
            if result?.status == 0 {
                reversed.insert(serial)
                log.info("adb reverse ok cho \(serial, privacy: .private)")
            } else {
                log.error("adb reverse lỗi cho \(serial, privacy: .private)")
            }
        }
    }

    /// Chạy adb ngoài luồng chính. Đầu ra ghi vào tệp tạm (không dùng pipe, tránh treo khi adb server con giữ pipe);
    /// quá 10 s thì SIGKILL và trả nil. Continuation chỉ resume đúng một lần.
    static func run(_ path: String, _ args: [String], timeout: DispatchTimeInterval = .seconds(10)) async -> (text: String, status: Int32)? {
        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("xdesk-adb-\(UUID().uuidString).txt")
        guard FileManager.default.createFile(atPath: outURL.path, contents: nil),
              let outHandle = try? FileHandle(forWritingTo: outURL) else { return nil }
        defer { try? FileManager.default.removeItem(at: outURL) }
        return await withCheckedContinuation { continuation in
            let once = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable ((text: String, status: Int32)?) -> Void = { value in
                let first = once.withLock { done -> Bool in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(returning: value) }
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            process.standardOutput = outHandle
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { proc in
                try? outHandle.close()
                let data = (try? Data(contentsOf: outURL)) ?? Data()
                finish((String(decoding: data, as: UTF8.self), proc.terminationStatus))
            }
            do { try process.run() } catch {
                try? outHandle.close()
                finish(nil)
                return
            }
            let pid = process.processIdentifier
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                // Chỉ kill khi chưa kết thúc, tránh bắn nhầm pid đã được tái dùng.
                if !once.withLock({ $0 }) { kill(pid, SIGKILL) }
                finish(nil)
            }
        }
    }
}
