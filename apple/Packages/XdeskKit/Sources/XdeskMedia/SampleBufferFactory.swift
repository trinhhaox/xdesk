import CoreMedia
import Foundation
import XdeskWire

/// Dựng `CMSampleBuffer` (DisplayImmediately) từ access unit Annex B. Giữ format description theo tham số mới nhất;
/// khung đến trước keyframe đầu tiên (chưa có tham số) → `nil` (người gọi nên gửi `keyframe.request`).
/// Một luồng giải mã dùng một factory; không thread-safe.
public struct SampleBufferFactory {
    private let assembler: FrameAssembler
    private var parameterSets: [[UInt8]] = []
    public private(set) var formatDescription: CMVideoFormatDescription?

    public init(codec: VideoCodec) { assembler = FrameAssembler(codec: codec) }

    public mutating func makeSampleBuffer(annexB: [UInt8], ptsMs: UInt32, isKeyframe: Bool) throws -> CMSampleBuffer? {
        let unit = try assembler.parse(annexB: annexB)
        if !unit.parameterSets.isEmpty, unit.parameterSets != parameterSets {
            formatDescription = try ParameterSets.makeFormatDescription(unit.parameterSets, codec: assembler.codec)
            parameterSets = unit.parameterSets
        }
        guard let formatDescription else { return nil }
        return try Self.build(avcc: unit.avcc, format: formatDescription, ptsMs: ptsMs, isKeyframe: isKeyframe)
    }

    private static func build(avcc: [UInt8], format: CMVideoFormatDescription, ptsMs: UInt32, isKeyframe: Bool) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: avcc.count, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: avcc.count, flags: 0, blockBufferOut: &block
        )
        guard status == kCMBlockBufferNoErr, let block else { throw MediaError.sampleBufferFailed(status) }
        status = CMBlockBufferReplaceDataBytes(with: avcc, blockBuffer: block, offsetIntoDestination: 0, dataLength: avcc.count)
        guard status == kCMBlockBufferNoErr else { throw MediaError.sampleBufferFailed(status) }

        var timing = CMSampleTimingInfo(
            duration: .invalid, presentationTimeStamp: CMTime(value: Int64(ptsMs), timescale: 1000), decodeTimeStamp: .invalid
        )
        var size = avcc.count
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
            sampleBufferOut: &sample
        )
        guard status == noErr, let sample else { throw MediaError.sampleBufferFailed(status) }
        try markAttachments(sample, isKeyframe: isKeyframe)
        return sample
    }

    private static func markAttachments(_ sample: CMSampleBuffer, isKeyframe: Bool) throws {
        guard let array = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(array) > 0 else {
            throw MediaError.sampleBufferFailed(kCMSampleBufferError_RequiredParameterMissing)
        }
        // Chuẩn CoreMedia: phần tử của mảng attachment là CFMutableDictionary.
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(array, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
        if !isKeyframe {
            CFDictionarySetValue(
                dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
    }
}
