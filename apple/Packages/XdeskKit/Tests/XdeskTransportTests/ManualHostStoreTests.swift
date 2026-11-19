import Foundation
import Testing
@testable import XdeskTransport

@Suite struct ManualHostStoreTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("xdesk-mh-\(UUID().uuidString)").appendingPathComponent("manual-hosts.json")
    }

    @Test func parsesTailscaleAndMagicDnsAddresses() {
        #expect(ManualHostAddress("100.101.102.103")?.normalized == "100.101.102.103:47800")
        #expect(ManualHostAddress(" 100.64.0.9:5000 ")?.port == 5000)
        #expect(ManualHostAddress("Mac-Mini.tail1234.ts.net:47801")?.normalized == "mac-mini.tail1234.ts.net:47801")
        #expect(ManualHostAddress("macbook")?.host == "macbook")
    }

    @Test func rejectsMalformedAddresses() {
        for bad in ["", ":47800", "100.1.2:47800", "100.1.2.3.4", "host:0", "host:70000", "a:b:c", "-bad.example", "sp ace", "mac..local", "http://x"] {
            #expect(ManualHostAddress(bad) == nil, "\(bad)")
        }
    }

    @Test func addListRemoveSurvivesReload() async throws {
        let file = tempFile()
        let store = ManualHostStore(fileURL: file)
        try await store.add(address: "100.101.102.103", name: "Mac nhà")
        try await store.add(address: "mac.tail1.ts.net:47800")
        #expect(await store.hosts.count == 2)
        try await store.remove(address: "mac.tail1.ts.net:47800")
        let reopened = ManualHostStore(fileURL: file)
        let hosts = await reopened.hosts
        #expect(hosts.map(\.address) == ["100.101.102.103:47800"])
        #expect(hosts.first?.name == "Mac nhà")
    }

    @Test func recordsLastAddressAndOrdersByRecentUse() async throws {
        let store = ManualHostStore(fileURL: tempFile())
        try await store.add(address: "a.ts.net")
        try await store.add(address: "b.ts.net")
        try await store.recordConnection(address: "b.ts.net:47800", resolved: "100.64.1.2:47800")
        let hosts = await store.hosts
        #expect(hosts.first?.address == "b.ts.net:47800")
        #expect(hosts.first?.lastAddress == "100.64.1.2:47800")
        #expect(hosts.last?.lastAddress == nil)
    }

    @Test func duplicateUpdatesNameAndInvalidOrFullThrow() async throws {
        let store = ManualHostStore(fileURL: tempFile())
        try await store.add(address: "100.64.0.1", name: "A")
        try await store.add(address: "100.64.0.1:47800", name: "B")
        #expect(await store.hosts.count == 1)
        #expect(await store.hosts.first?.name == "B")
        await #expect(throws: ManualHostError.invalidAddress) { try await store.add(address: "???") }
        for index in 0..<(ManualHostStore.maxHosts - 1) { try await store.add(address: "h\(index).ts.net") }
        await #expect(throws: ManualHostError.limitReached) { try await store.add(address: "extra.ts.net") }
    }

    @Test func corruptFileIsKeptAsBadAndStartsEmpty() async throws {
        let file = tempFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("không phải json".utf8).write(to: file)
        let store = ManualHostStore(fileURL: file)
        #expect(await store.hosts.isEmpty)
        #expect(await store.loadError != nil)
        #expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("bad").path))
    }
}
