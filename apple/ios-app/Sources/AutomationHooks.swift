#if DEBUG
import Foundation
import XdeskCrypto
import XdeskViewer
import XdeskWire

/// Chỉ build Debug: điều khiển bằng tham số dòng lệnh để kiểm thử qua `devicectl ... launch --console`.
///   --auto-connect host:port   tự kết nối khi mở app
///   --plaintext                tắt mã hoá (chỉ Debug; mặc định Debug cũng mã hoá và dùng ghép đôi thật)
///   --pair-token <uri|@file>   ghép đôi bằng QR (URI xdesk://pair?... hoặc đường dẫn file chứa URI)
///   --mode extend|mirror       chọn chế độ hiển thị trước khi kết nối
///   --quit-after <giây>        tự thoát (kèm bye)
/// In `xdesk-stats ...` mỗi 2 giây ra stderr để đọc từ console.
@MainActor
enum AutomationHooks {
    static func run(_ model: StreamViewModel) async {
        let args = CommandLine.arguments
        if let mode = value(after: "--mode", in: args).flatMap(ScreenMode.init(rawValue:)) { model.screenMode = mode }
        if let backend = model.security?.identityBackend { report("xdesk-security identityBackend=\(backend) dataProtection=\(model.security?.usesDataProtectionKeychain ?? false)") }
        if let error = model.securityError { report("xdesk-security error=\(error)") }
        try? await Task.sleep(for: .seconds(1))
        if let token = value(after: "--pair-token", in: args) {
            let text = token.hasPrefix("@") ? ((try? String(contentsOfFile: String(token.dropFirst()), encoding: .utf8)) ?? "") : token
            guard let uri = try? PairingURI.parse(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { report("pair-token: URI không hợp lệ"); return }
            await model.pair(with: uri)
        } else {
            guard let hostPort = value(after: "--auto-connect", in: args) else { return }
            guard let target = ViewerTarget.parse(manual: hostPort) else { report("auto-connect: sai định dạng \(hostPort)"); return }
            await model.connect(to: target)
        }
        report("auto-connect state=\(model.session.state) error=\(model.errorMessage ?? "-")")
        let quitAfter = value(after: "--quit-after", in: args).flatMap(Double.init)
        let started = ContinuousClock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            let session = model.session
            report("xdesk-stats state=\(session.state) fps=\(session.fps) kbps=\(session.recvKbps) rttMs=\(session.rttMs ?? -1)")
            if let quitAfter, ContinuousClock.now - started > .seconds(quitAfter) {
                await model.disconnect()
                exit(0)
            }
        }
    }

    private static func report(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
}
#endif
