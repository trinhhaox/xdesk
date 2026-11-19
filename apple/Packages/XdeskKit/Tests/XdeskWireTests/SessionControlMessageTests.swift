import Testing
@testable import XdeskWire

@Suite struct SessionControlMessageTests {
    private func roundTrip(_ message: ControlMessage, id: UInt32 = 5) throws -> ControlEnvelope {
        try ControlMessageCodec.decode(ControlMessageCodec.encode(ControlEnvelope(id: id, message: message)))
    }

    @Test func rekeyHasNoBody() throws {
        let bytes = try ControlMessageCodec.encode(ControlEnvelope(id: 0, message: .rekey))
        #expect(String(decoding: bytes, as: UTF8.self) == #"{"id":0,"t":"rekey"}"#)
        #expect(try roundTrip(.rekey, id: 0).message == .rekey)
    }

    @Test func resyncCarriesEpochAndAskFlag() throws {
        let message = ControlMessage.rekeyResync(RekeyResync(epoch: 9, ask: true))
        let bytes = try ControlMessageCodec.encode(ControlEnvelope(id: 2, message: message))
        #expect(String(decoding: bytes, as: UTF8.self) == #"{"ask":true,"epoch":9,"id":2,"t":"rekey.resync"}"#)
        #expect(try roundTrip(message, id: 2).message == message)
    }

    @Test func pairResultRoundTrips() throws {
        for accepted in [true, false] {
            #expect(try roundTrip(.pairResult(PairResult(accepted: accepted))).message == .pairResult(PairResult(accepted: accepted)))
        }
    }

    @Test func malformedResyncIsRejected() {
        #expect(throws: WireError.self) {
            _ = try ControlMessageCodec.decode(Array(#"{"id":1,"t":"rekey.resync","epoch":"x","ask":true}"#.utf8))
        }
    }

    @Test func encryptedBulkFrameMayCarryTheTag() throws {
        let frame = ControlFrame(kind: .bulk, payload: [UInt8](repeating: 0, count: ControlFrame.maxBulkPayload + 16))
        #expect(throws: WireError.self) { _ = try ControlFrameCodec.encode(frame) }
        let bytes = try ControlFrameCodec.encode(frame, extraBulkAllowance: 16)
        #expect(try ControlFrameCodec.decode(bytes, extraBulkAllowance: 16)?.consumed == bytes.count)
        #expect(throws: WireError.self) { _ = try ControlFrameCodec.decode(bytes) }
    }
}
