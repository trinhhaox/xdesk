import Foundation
import Testing
@testable import XdeskWire

@Suite struct ClipboardMessageTests {
    private let hash = String(repeating: "ab", count: 32)

    private func encode(_ message: ControlMessage) throws -> String {
        String(decoding: try ControlMessageCodec.encode(ControlEnvelope(id: 3, message: message)), as: UTF8.self)
    }

    @Test func offerCarriesHashAndOldOfferStillDecodes() throws {
        let offer = ControlMessage.clipOffer(ClipOffer(kind: .text, size: 12, hash: hash))
        #expect(try encode(offer) == "{\"hash\":\"\(hash)\",\"id\":3,\"kind\":\"text\",\"size\":12,\"t\":\"clip.offer\"}")
        let old = try ControlMessageCodec.decode(Array("{\"t\":\"clip.offer\",\"id\":1,\"kind\":\"image\",\"size\":9}".utf8))
        #expect(old.message == .clipOffer(ClipOffer(kind: .image, size: 9)))
    }

    @Test func clipDataRoundTripsInCanonicalForm() throws {
        let message = ControlMessage.clipData(ClipData(kind: .image, size: 70_000, hash: hash))
        let json = try encode(message)
        #expect(json == "{\"hash\":\"\(hash)\",\"id\":3,\"kind\":\"image\",\"size\":70000,\"t\":\"clip.data\"}")
        #expect(try ControlMessageCodec.decode(Array(json.utf8)).message == message)
    }

    @Test func sizeLimitsAreEnforced() throws {
        let max = UInt32(ClipLimits.maxBytes)
        _ = try encode(.clipData(ClipData(kind: .text, size: max, hash: hash)))
        expectWireError("invalidField") { _ = try encode(.clipData(ClipData(kind: .text, size: max + 1, hash: hash))) }
        expectWireError("invalidField") { _ = try encode(.clipData(ClipData(kind: .text, size: 0, hash: hash))) }
        expectWireError("invalidField") { _ = try encode(.clipOffer(ClipOffer(kind: .text, size: max + 1))) }
        expectWireError("invalidField") { _ = try encode(.clipOffer(ClipOffer(kind: .text, size: 0))) }
    }

    @Test func hashMustBeLowercaseSha256Hex() {
        for bad in ["", "abc", String(repeating: "AB", count: 32), String(repeating: "zz", count: 32), String(repeating: "a", count: 65)] {
            expectWireError("invalidField") { _ = try encode(.clipData(ClipData(kind: .text, size: 1, hash: bad))) }
            expectWireError("invalidField") { _ = try encode(.clipOffer(ClipOffer(kind: .text, size: 1, hash: bad))) }
        }
    }
}
