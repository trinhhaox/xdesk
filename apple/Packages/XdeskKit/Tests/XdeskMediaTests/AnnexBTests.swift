import Testing
@testable import XdeskMedia

@Suite struct AnnexBTests {
    @Test func avccToAnnexBAndBack() throws {
        let nalA: [UInt8] = [0x67, 1, 2, 3]
        let nalB: [UInt8] = [0x65, 9, 9]
        let avcc = AnnexB.toAVCC([nalA, nalB])
        #expect(avcc == [0, 0, 0, 4, 0x67, 1, 2, 3, 0, 0, 0, 3, 0x65, 9, 9])
        let annexB = try AnnexB.fromAVCC(avcc, lengthSize: 4)
        #expect(annexB == [0, 0, 0, 1, 0x67, 1, 2, 3, 0, 0, 0, 1, 0x65, 9, 9])
        #expect(AnnexB.splitNALUnits(annexB) == [nalA, nalB])
    }

    @Test func splitAcceptsThreeByteStartCodes() {
        let data: [UInt8] = [0, 0, 1, 0x41, 5, 0, 0, 1, 0x41, 6]
        #expect(AnnexB.splitNALUnits(data) == [[0x41, 5], [0x41, 6]])
        #expect(AnnexB.splitNALUnits([1, 2, 3]).isEmpty)
    }

    @Test func malformedAVCCThrowsInsteadOfTrapping() {
        #expect(throws: MediaError.self) { try AnnexB.fromAVCC([0, 0, 0, 9, 1], lengthSize: 4) }
        #expect(throws: MediaError.self) { try AnnexB.fromAVCC([0, 0], lengthSize: 4) }
        #expect(throws: MediaError.self) { try AnnexB.fromAVCC([0, 0, 0, 0], lengthSize: 4) }
        #expect(throws: MediaError.self) { try AnnexB.fromAVCC([1], lengthSize: 5) }
    }

    @Test func settingsValidation() throws {
        try EncoderSettings(width: 640, height: 360).validate()
        #expect(throws: MediaError.self) { try EncoderSettings(width: 0, height: 360).validate() }
        #expect(throws: MediaError.self) { try EncoderSettings(width: 640, height: 360, fps: 0).validate() }
        #expect(throws: MediaError.self) { try EncoderSettings(width: 640, height: 360, bitrateKbps: 1).validate() }
    }
}
