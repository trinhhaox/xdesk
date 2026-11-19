import Foundation
import Testing
import XdeskCrypto
import XdeskTransport
@testable import XdeskViewer

@Suite struct PairedHostListingTests {
    private func host(_ seed: UInt8, name: String, address: String? = nil, role: DeviceRole = .host, seen: Date? = nil) -> PairedDevice {
        var device = PairedDevice(name: name, publicKey: [UInt8](repeating: seed, count: 32), role: role, createdAt: .distantPast, lastSeen: seen)
        device.lastAddress = address
        return device
    }

    private func manual(_ address: String, resolved: String? = nil) throws -> ManualHost {
        var json = #"{"address":"\#(address)","name":"x""#
        if let resolved { json += #","lastAddress":"\#(resolved)""# }
        return try JSONDecoder().decode(ManualHost.self, from: Data((json + "}").utf8))
    }

    @Test func statusReadyViaAddressOffline() {
        let a = host(1, name: "A"), b = host(2, name: "B", address: "100.64.0.2:47800"), c = host(3, name: "C")
        let rows = PairedHostListing.rows(paired: [c, b, a], discoveredIds: [a.id], manual: [])
        #expect(rows.map(\.device.name) == ["A", "B", "C"])
        #expect(rows.map(\.status) == [.ready, .viaAddress("100.64.0.2:47800"), .offline])
        #expect(rows[1].status.text == "Qua địa chỉ 100.64.0.2:47800")
    }

    @Test func discoveredWinsOverAddressAndNoDuplicate() throws {
        let a = host(1, name: "A", address: "mac.ts.net:47800")
        let saved = try manual("mac.ts.net:47800")
        let rows = PairedHostListing.rows(paired: [a], discoveredIds: [a.id], manual: [saved])
        #expect(rows.count == 1)
        #expect(rows[0].status == .ready)
        #expect(rows[0].savedAddresses == ["mac.ts.net:47800"])
        #expect(PairedHostListing.unmergedManual([saved], rows: rows).isEmpty)
    }

    @Test func manualMatchedByResolvedAddressAndUnrelatedKept() throws {
        let a = host(1, name: "A", address: "100.64.0.9:47800")
        let viaDns = try manual("mac.ts.net:47800", resolved: "100.64.0.9:47800")
        let other = try manual("10.0.0.5:47800")
        let rows = PairedHostListing.rows(paired: [a], discoveredIds: [], manual: [viaDns, other])
        #expect(rows[0].savedAddresses == ["mac.ts.net:47800"])
        #expect(PairedHostListing.unmergedManual([viaDns, other], rows: rows) == [other])
    }

    @Test func ignoresViewerRoleAndSeparatesUnpaired() {
        let a = host(1, name: "A"), viewer = host(4, name: "Phone", role: .viewer)
        let rows = PairedHostListing.rows(paired: [a, viewer], discoveredIds: [], manual: [])
        #expect(rows.map(\.id) == [a.id])
        #expect(PairedHostListing.unpairedIds(discoveredIds: [a.id, "ZZ"], rows: rows) == ["ZZ"])
    }

    @Test func sameStatusOrderedByMostRecentlySeen() {
        let old = host(1, name: "Old", seen: Date(timeIntervalSince1970: 10)), new = host(2, name: "New", seen: Date(timeIntervalSince1970: 99))
        #expect(PairedHostListing.rows(paired: [old, new], discoveredIds: [], manual: []).map(\.device.name) == ["New", "Old"])
    }
}
