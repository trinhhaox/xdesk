import Foundation
import Testing
@testable import Xdesk

@Suite struct AdbReverseWatcherTests {
    @Test func parsesOnlyAuthorizedDevices() {
        let output = """
        List of devices attached
        R58N12ABCDE\tdevice
        100.76.122.48:5555\tdevice
        emulator-5554\toffline
        XYZ987\tunauthorized

        """
        #expect(AdbReverseWatcher.parseDevices(output) == ["R58N12ABCDE", "100.76.122.48:5555"])
    }

    @Test func emptyListYieldsNoDevices() {
        #expect(AdbReverseWatcher.parseDevices("List of devices attached\n\n").isEmpty)
        #expect(AdbReverseWatcher.parseDevices("").isEmpty)
    }

    @Test func prefersSdkFromEnvironment() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let tools = dir.appendingPathComponent("platform-tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let adb = tools.appendingPathComponent("adb")
        try Data("#!/bin/sh\n".utf8).write(to: adb)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adb.path)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(AdbReverseWatcher.locateAdb(environment: ["ANDROID_HOME": dir.path]) == adb.path)
    }

    @Test func runCapturesOutputAndStatus() async {
        let result = await AdbReverseWatcher.run("/bin/sh", ["-c", "echo hello; exit 3"])
        #expect(result?.text == "hello\n")
        #expect(result?.status == 3)
    }

    @Test func runTimesOutInsteadOfHanging() async {
        let clock = ContinuousClock()
        let start = clock.now
        let result = await AdbReverseWatcher.run("/bin/sleep", ["30"], timeout: .milliseconds(300))
        #expect(result == nil)
        #expect(clock.now - start < .seconds(5))
    }

    @Test func runReturnsNilForMissingBinary() async {
        #expect(await AdbReverseWatcher.run("/nonexistent/adb", ["devices"]) == nil)
    }
}
