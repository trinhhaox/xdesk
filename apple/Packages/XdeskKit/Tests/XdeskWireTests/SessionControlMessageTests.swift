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

@Suite struct AgentApproveMessageTests {
    private func roundTrip(_ message: ControlMessage) throws -> ControlMessage {
        try ControlMessageCodec.decode(ControlMessageCodec.encode(ControlEnvelope(id: 7, message: message))).message
    }

    @Test func requestAndResponseRoundTrip() throws {
        let request = AgentApprove.request(requestId: "req-1", agentName: "Claude", summary: "Mở TextEdit", expiresAt: 1_700_000_060_000)
        #expect(try roundTrip(.agentApprove(request)) == .agentApprove(request))
        #expect(request.isRequest)
        let response = AgentApprove.response(requestId: "req-1", allow: true)
        #expect(try roundTrip(.agentApprove(response)) == .agentApprove(response))
        #expect(!response.isRequest)
    }

    @Test func wireFormIsFlatSortedJson() throws {
        let bytes = try ControlMessageCodec.encode(ControlEnvelope(id: 3, message: .agentApprove(.response(requestId: "r", allow: false))))
        #expect(String(decoding: bytes, as: UTF8.self) == #"{"allow":false,"id":3,"requestId":"r","t":"agent.approve"}"#)
    }

    @Test func oversizedOrEmptyFieldsAreRejected() {
        #expect(throws: WireError.self) { _ = try ControlMessageCodec.encode(ControlEnvelope(id: 1, message: .agentApprove(.response(requestId: "", allow: true)))) }
        let long = String(repeating: "a", count: AgentApprove.maxSummaryBytes + 1)
        #expect(throws: WireError.self) {
            _ = try ControlMessageCodec.encode(ControlEnvelope(id: 1, message: .agentApprove(.request(requestId: "r", agentName: "a", summary: long, expiresAt: 1))))
        }
    }

    @Test func olderViewerTreatsItAsUnknown() throws {
        // Bộ giải mã của viewer cũ không có case này: type lạ phải ra `.unknown`, không lỗi.
        let message = try ControlMessageCodec.decode(Array(#"{"id":9,"t":"agent.approve.v2","requestId":"x"}"#.utf8)).message
        #expect(message == .unknown(type: "agent.approve.v2"))
    }
}
