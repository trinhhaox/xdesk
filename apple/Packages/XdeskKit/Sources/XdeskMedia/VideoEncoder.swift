import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import XdeskWire

/// Một access unit đã mã hoá, dạng Annex B (keyframe có kèm tham số SPS/PPS hoặc VPS/SPS/PPS ở đầu).
public struct EncodedFrame: Sendable, Equatable {
    public let data: [UInt8]
    public let isKeyframe: Bool
    public let ptsMs: UInt32
}

/// Bộ mã hoá VideoToolbox độ trễ thấp: RealTime, không sắp xếp lại khung, `MaxFrameDelayCount` 0, keyframe dài + theo yêu cầu.
/// `encode` gọi từ một luồng capture; kết quả ra `frames` (kết thúc bằng lỗi nếu mã hoá hỏng).
/// `@unchecked Sendable`: `VTCompressionSession` an toàn đa luồng, trạng thái còn lại nằm sau `lock`.
public final class VideoEncoder: @unchecked Sendable {
    public let frames: AsyncThrowingStream<EncodedFrame, any Error>
    /// `false` nếu máy từ chối `EnableLowLatencyRateControl` và phải dùng chế độ thường.
    public let usesLowLatencyRateControl: Bool
    private let continuation: AsyncThrowingStream<EncodedFrame, any Error>.Continuation
    private let session: VTCompressionSession
    private let codec: VideoCodec
    private let lock = NSLock()
    private var keyframeRequested = false
    private var finished = false

    public init(settings: EncoderSettings) throws {
        try settings.validate()
        (frames, continuation) = AsyncThrowingStream.makeStream(of: EncodedFrame.self, throwing: (any Error).self)
        codec = settings.codec
        let (created, lowLatency) = try Self.createSession(settings)
        session = created
        usesLowLatencyRateControl = lowLatency
        try configure(settings)
        let status = VTCompressionSessionPrepareToEncodeFrames(session)
        guard status == noErr else { throw MediaError.sessionCreationFailed(status) }
    }

    deinit { invalidate() }

    private static func createSession(_ s: EncoderSettings) throws -> (VTCompressionSession, Bool) {
        let codecType: CMVideoCodecType = s.codec == .h264 ? kCMVideoCodecType_H264 : kCMVideoCodecType_HEVC
        var lastStatus: OSStatus = noErr
        for lowLatency in [true, false] {
            let spec: [CFString: Any] = lowLatency ? [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true] : [:]
            var out: VTCompressionSession?
            lastStatus = VTCompressionSessionCreate(
                allocator: nil, width: Int32(s.width), height: Int32(s.height), codecType: codecType,
                encoderSpecification: spec as CFDictionary, imageBufferAttributes: nil, compressedDataAllocator: nil,
                outputCallback: nil, refcon: nil, compressionSessionOut: &out
            )
            if lastStatus == noErr, let out { return (out, lowLatency) }
        }
        throw MediaError.sessionCreationFailed(lastStatus)
    }

    private func configure(_ s: EncoderSettings) throws {
        try set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        try set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        try setMaxFrameDelayZero()
        try set(kVTCompressionPropertyKey_ExpectedFrameRate, s.fps as CFNumber)
        try set(kVTCompressionPropertyKey_MaxKeyFrameInterval, (s.fps * s.keyframeIntervalSeconds) as CFNumber)
        try set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, s.keyframeIntervalSeconds as CFNumber)
        try set(kVTCompressionPropertyKey_ProfileLevel, s.codec == .h264 ? kVTProfileLevel_H264_High_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel)
        try setSingleReferenceBuffer()
        try setBitrate(kbps: s.bitrateKbps)
    }

    /// Low-latency rate control đã mặc định không trễ khung và từ chối thuộc tính này (`kVTPropertyNotSupportedErr`).
    private func setMaxFrameDelayZero() throws {
        let status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 0 as CFNumber)
        guard status == noErr || (status == kVTPropertyNotSupportedErr && usesLowLatencyRateControl) else {
            throw MediaError.propertyRejected(name: kVTCompressionPropertyKey_MaxFrameDelayCount as String, status: status)
        }
    }

    /// Một khung tham chiếu duy nhất: SPS ra `max_num_ref_frames = 1`, `max_dec_frame_buffering = 1`, không long-term ref.
    /// Mặc định VideoToolbox (low-latency) khai báo 8 → decoder Unisoc/MediaTek giữ ~6 khung trước khi xuất.
    /// Chỉ áp cho H.264; máy từ chối thuộc tính (macOS cũ) thì dùng mặc định, không lỗi.
    private func setSingleReferenceBuffer() throws {
        guard codec == .h264 else { return }
        let status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ReferenceBufferCount, value: 1 as CFNumber)
        guard status == noErr || status == kVTPropertyNotSupportedErr else {
            throw MediaError.propertyRejected(name: kVTCompressionPropertyKey_ReferenceBufferCount as String, status: status)
        }
    }

    private func set(_ key: CFString, _ value: CFTypeRef) throws {
        let status = VTSessionSetProperty(session, key: key, value: value)
        guard status == noErr else { throw MediaError.propertyRejected(name: key as String, status: status) }
    }

    /// Đổi bitrate trung bình lúc chạy (ABR).
    public func setBitrate(kbps: Int) throws {
        try set(kVTCompressionPropertyKey_AverageBitRate, (kbps * 1000) as CFNumber)
    }

    /// Khung kế tiếp sẽ là keyframe (`keyframe.request`).
    public func requestKeyframe() {
        lock.lock()
        keyframeRequested = true
        lock.unlock()
    }

    private func takeKeyframeRequest() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        defer { keyframeRequested = false }
        return keyframeRequested
    }

    public func encode(_ pixelBuffer: CVPixelBuffer, ptsMs: UInt32) throws {
        let options: CFDictionary? = takeKeyframeRequest() ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer, presentationTimeStamp: CMTime(value: Int64(ptsMs), timescale: 1000),
            duration: .invalid, frameProperties: options, infoFlagsOut: nil
        ) { [self] status, flags, sampleBuffer in
            deliver(status: status, flags: flags, sampleBuffer: sampleBuffer)
        }
        guard status == noErr else { throw MediaError.encodeFailed(status) }
    }

    /// Chờ mọi khung đang mã hoá ra hết.
    public func flush() throws {
        let status = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        guard status == noErr else { throw MediaError.encodeFailed(status) }
    }

    /// Đóng phiên và kết thúc `frames`. Idempotent.
    public func invalidate() {
        lock.lock()
        let already = finished
        finished = true
        lock.unlock()
        guard !already else { return }
        VTCompressionSessionInvalidate(session)
        continuation.finish()
    }

    private func deliver(status: OSStatus, flags: VTEncodeInfoFlags, sampleBuffer: CMSampleBuffer?) {
        guard status == noErr else { continuation.finish(throwing: MediaError.encodeFailed(status)); return }
        guard !flags.contains(.frameDropped), let sampleBuffer else { return }
        do {
            continuation.yield(try Self.makeFrame(from: sampleBuffer, codec: codec))
        } catch {
            continuation.finish(throwing: error)
        }
    }

    /// AVCC → Annex B; keyframe được thêm tham số từ format description.
    static func makeFrame(from sampleBuffer: CMSampleBuffer, codec: VideoCodec) throws -> EncodedFrame {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer), let fd = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw MediaError.sampleBufferFailed(kCMSampleBufferError_RequiredParameterMissing)
        }
        var avcc = [UInt8](repeating: 0, count: CMBlockBufferGetDataLength(block))
        let copy = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: avcc.count, destination: &avcc)
        guard copy == kCMBlockBufferNoErr else { throw MediaError.sampleBufferFailed(copy) }
        let notSync = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]])?
            .first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        let (sets, lengthSize) = try ParameterSets.extract(from: fd, codec: codec)
                var data = notSync ? [] : AnnexB.fromParameterSets(sets)
        data += try AnnexB.fromAVCC(avcc, lengthSize: lengthSize)
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        return EncodedFrame(data: data, isKeyframe: !notSync, ptsMs: UInt32(clamping: Int64(pts.seconds * 1000)))
    }
}
