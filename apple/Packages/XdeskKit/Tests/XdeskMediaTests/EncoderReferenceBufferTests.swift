import CoreVideo
import Foundation
import Testing
@testable import XdeskMedia

/// Decoder phần cứng Unisoc/MediaTek giữ cả DPB khai báo trong SPS trước khi xuất khung; encoder phải khai báo đúng 1.
@Suite struct EncoderReferenceBufferTests {
    /// `max_num_ref_frames` của SPS H.264 profile High không có scaling matrix (đủ cho đầu ra VideoToolbox).
    private func maxNumRefFrames(sps: [UInt8]) -> Int? {
        var bits: [Int] = []
        var zeros = 0
        for b in sps.dropFirst() {
            if zeros >= 2 && b == 3 { zeros = 0; continue }
            zeros = b == 0 ? zeros + 1 : 0
            for i in stride(from: 7, through: 0, by: -1) { bits.append(Int((b >> UInt8(i)) & 1)) }
        }
        var pos = 24 // profile, constraint, level
        func read(_ n: Int) -> Int { defer { pos += n }; return bits[pos..<pos + n].reduce(0) { ($0 << 1) | $1 } }
        func ue() -> Int { var z = 0; while read(1) == 0 { z += 1 }; return (1 << z) - 1 + read(z) }
        guard bits.count > 64, [100, 110, 122, 244].contains(sps[1]) else { return nil }
        _ = ue()
        guard ue() != 3 else { return nil }
        _ = ue(); _ = ue(); _ = read(1)
        guard read(1) == 0 else { return nil } // không có scaling matrix
        _ = ue()
        let pocType = ue()
        guard pocType != 1 else { return nil }
        if pocType == 0 { _ = ue() }
        return ue()
    }

    @Test(.timeLimit(.minutes(1))) func spsDeclaresSingleReferenceFrame() async throws {
        let encoder = try VideoEncoder(settings: EncoderSettings(width: 640, height: 360, fps: 30, bitrateKbps: 4000))
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, [kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()] as CFDictionary, &pixelBuffer)
        try encoder.encode(try #require(pixelBuffer), ptsMs: 0)
        var first: EncodedFrame?
        for try await frame in encoder.frames { first = frame; break }
        encoder.invalidate()
        let nals = AnnexB.splitNALUnits(try #require(first).data)
        let sps = try #require(nals.first { $0.first.map { $0 & 0x1F } == 7 })
        #expect(maxNumRefFrames(sps: sps) == 1)
    }
}
