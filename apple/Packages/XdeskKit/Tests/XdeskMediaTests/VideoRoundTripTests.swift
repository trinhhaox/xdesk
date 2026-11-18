import CoreMedia
import CoreVideo
import Foundation
import Testing
import VideoToolbox
import XdeskWire
@testable import XdeskMedia

/// Đếm khung giải mã được từ thread VideoToolbox.
final class DecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var errors: [OSStatus] = []

    func record(status: OSStatus) {
        lock.lock(); defer { lock.unlock() }
        if status == noErr { frames += 1 } else { errors.append(status) }
    }

    var decoded: Int { lock.lock(); defer { lock.unlock() }; return frames }
    var failures: [OSStatus] { lock.lock(); defer { lock.unlock() }; return errors }
}

private func syntheticFrame(index: Int, width: Int, height: Int) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()]
    let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attrs as CFDictionary, &buffer)
    let pixelBuffer = try #require(status == kCVReturnSuccess ? buffer : nil)
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    for plane in 0..<CVPixelBufferGetPlaneCount(pixelBuffer) {
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane) else { continue }
        let rows = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<rows {
            for x in 0..<stride { bytes[y * stride + x] = UInt8(truncatingIfNeeded: x * 3 + y * 5 + index * 7 + plane * 40) }
        }
    }
    return pixelBuffer
}

private func collect(_ encoder: VideoEncoder, expecting count: Int) async throws -> [EncodedFrame] {
    var out: [EncodedFrame] = []
    for try await frame in encoder.frames {
        out.append(frame)
        if out.count == count { break }
    }
    return out
}

@Suite struct VideoRoundTripTests {
    static let width = 640, height = 360, frameCount = 30

    /// Mã hoá thật → cắt gói → ghép (có đảo thứ tự) → SampleBufferFactory → giải mã VTDecompressionSession.
    @Test(.timeLimit(.minutes(1))) func encodePacketizeReassembleDecode() async throws {
        let settings = EncoderSettings(width: Self.width, height: Self.height, fps: 30, bitrateKbps: 4000)
        let encoder = try VideoEncoder(settings: settings)
        for i in 0..<Self.frameCount {
            try encoder.encode(try syntheticFrame(index: i, width: Self.width, height: Self.height), ptsMs: UInt32(i * 33))
        }
        try encoder.flush()
        let encoded = try await collect(encoder, expecting: Self.frameCount)
        encoder.invalidate()

        #expect(encoded.count == Self.frameCount)
        #expect(encoded[0].isKeyframe)
        #expect(encoded.dropFirst().allSatisfy { !$0.isKeyframe }, "keyframe interval dài: chỉ khung đầu là IDR")
        let firstNALs = AnnexB.splitNALUnits(encoded[0].data).map { $0[0] & 0x1F }
        #expect(firstNALs.starts(with: [7, 8]), "keyframe phải mang SPS/PPS: \(firstNALs)")

        let packetizer = Packetizer(streamId: 1)
        var reassembler = Reassembler()
        var assembled: [AssembledFrame] = []
        for (i, frame) in encoded.enumerated() {
            let packets = try packetizer.packetize(frame: frame.data, frameNo: UInt32(i), ptsMs: frame.ptsMs, isKeyframe: frame.isKeyframe)
            for packet in packets.reversed() {
                if let done = try reassembler.ingest(try MediaPacket.decode(try packet.encode()), nowMs: 0) { assembled.append(done) }
            }
        }
        #expect(assembled.count == Self.frameCount)
        #expect(assembled.map(\.isKeyframe) == encoded.map(\.isKeyframe))
        #expect(assembled.map(\.data) == encoded.map(\.data))

        var factory = SampleBufferFactory(codec: .h264)
        let counter = DecodeCounter()
        var decoder: VTDecompressionSession?
        for frame in assembled {
            let sample = try #require(try factory.makeSampleBuffer(annexB: frame.data, ptsMs: frame.ptsMs, isKeyframe: frame.isKeyframe))
            if decoder == nil {
                let format = try #require(factory.formatDescription)
                let status = VTDecompressionSessionCreate(allocator: nil, formatDescription: format, decoderSpecification: nil, imageBufferAttributes: nil, outputCallback: nil, decompressionSessionOut: &decoder)
                #expect(status == noErr)
            }
            let session = try #require(decoder)
            let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: nil) { status, _, image, _, _ in
                counter.record(status: image == nil && status == noErr ? kVTInvalidSessionErr : status)
            }
            #expect(status == noErr)
        }
        if let decoder { VTDecompressionSessionWaitForAsynchronousFrames(decoder); VTDecompressionSessionInvalidate(decoder) }
        #expect(counter.failures.isEmpty, "\(counter.failures)")
        #expect(counter.decoded == Self.frameCount)
    }

    @Test(.timeLimit(.minutes(1))) func requestedKeyframeIsForced() async throws {
        let encoder = try VideoEncoder(settings: EncoderSettings(width: Self.width, height: Self.height, fps: 30))
        let total = 6
        for i in 0..<total {
            if i == 4 { encoder.requestKeyframe() }
            try encoder.encode(try syntheticFrame(index: i, width: Self.width, height: Self.height), ptsMs: UInt32(i * 33))
        }
        try encoder.flush()
        let frames = try await collect(encoder, expecting: total)
        encoder.invalidate()
        #expect(frames.map(\.isKeyframe) == [true, false, false, false, true, false])
        #expect(AnnexB.splitNALUnits(frames[4].data).first.map { $0[0] & 0x1F } == 7, "keyframe ép buộc vẫn mang SPS đầu tiên")
    }

    @Test(.timeLimit(.minutes(1))) func bitrateChangesAtRuntimeAndBadSettingsThrow() throws {
        let encoder = try VideoEncoder(settings: EncoderSettings(width: Self.width, height: Self.height, fps: 30))
        try encoder.setBitrate(kbps: 2500)
        encoder.invalidate()
        #expect(throws: MediaError.self) { _ = try VideoEncoder(settings: EncoderSettings(width: 3, height: 3)) }
    }

    @Test func deltaFrameBeforeKeyframeYieldsNil() throws {
        var factory = SampleBufferFactory(codec: .h264)
        let sample = try factory.makeSampleBuffer(annexB: [0, 0, 0, 1, 0x41, 1, 2, 3], ptsMs: 0, isKeyframe: false)
        #expect(sample == nil)
        #expect(throws: MediaError.self) { _ = try factory.makeSampleBuffer(annexB: [9, 9, 9], ptsMs: 0, isKeyframe: false) }
    }
}
