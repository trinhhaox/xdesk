import SwiftUI

/// Điểm vào của app. Khi `xcodebuild test` dùng Xdesk.app làm test host, chỉ chạy một app rỗng:
/// không mở Keychain (bản build test ký khác nên login keychain hỏi mật khẩu liên tục), không chia sẻ cổng 47800
/// tranh với app Xdesk thật, không bật USB hay MCP.
@main
enum XdeskMain {
    static func main() {
        if RuntimeEnvironment.isUnitTestHost { TestHostApp.main() } else { XdeskApp.main() }
    }
}

enum RuntimeEnvironment {
    /// XCTest/Swift Testing đặt các biến này cho tiến trình test host.
    static let isUnitTestHost: Bool = {
        let env = ProcessInfo.processInfo.environment
        return ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"].contains { env[$0] != nil }
    }()
}

private struct TestHostApp: App {
    var body: some Scene { Settings { EmptyView() } }
}
