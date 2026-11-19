import AVFoundation
import AudioToolbox
import XdeskWire

public enum AudioCodecError: Error, Sendable, Equatable {
    case unavailable
    case encodeFailed(String)
    case decodeFailed(String)
}

enum AacEldFormat {
    static let pcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(AudioPayload.sampleRate), channels: 2, interleaved: true)
    static let compressed: AVAudioFormat? = {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Double(AudioPayload.sampleRate), mFormatID: kAudioFormatMPEG4AAC_ELD, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: UInt32(AudioPayload.aacFramesPerUnit), mBytesPerFrame: 0,
            mChannelsPerFrame: 2, mBitsPerChannel: 0, mReserved: 0)
        return AVAudioFormat(streamDescription: &asbd)
    }()
}

/// PCM s16 stereo 48 kHz → access unit AAC-ELD (AudioToolbox qua `AVAudioConverter`), ~96 kb/s. Không thread-safe: dùng từ một luồng.
public final class AacEldEncoder: @unchecked Sendable {
    public static let bitRate = 96_000
    private let converter: AVAudioConverter
    private let compressed: AVAudioFormat
    private let pcm: AVAudioFormat

    public init() throws {
        guard let pcm = AacEldFormat.pcm, let compressed = AacEldFormat.compressed, let converter = AVAudioConverter(from: pcm, to: compressed)
        else { throw AudioCodecError.unavailable }
        converter.bitRate = Self.bitRate
        (self.pcm, self.compressed, self.converter) = (pcm, compressed, converter)
    }

    /// Cookie (esds) của bộ mã hoá; chứa AudioSpecificConfig `AudioPayload.aacEldConfig` (test đối chiếu).
    public var magicCookie: [UInt8]? { converter.magicCookie.map { [UInt8]($0) } }

    /// Đúng 512 mẫu/kênh xen kẽ → một access unit; `nil` khi bộ mã hoá chưa trả gì (mồi).
    public func encode(_ samples: [Int16]) throws -> [UInt8]? {
        let frames = AudioPayload.aacFramesPerUnit
        guard samples.count == frames * AudioPayload.channels,
              let input = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: AVAudioFrameCount(frames)),
              let channel = input.int16ChannelData?[0]
        else { throw AudioCodecError.encodeFailed("đầu vào không đủ \(frames) mẫu") }
        input.frameLength = AVAudioFrameCount(frames)
        samples.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress { channel.update(from: base, count: buffer.count) }
        }
        let output = AVAudioCompressedBuffer(format: compressed, packetCapacity: 4, maximumPacketSize: converter.maximumOutputPacketSize)
        var fed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if fed { state.pointee = .noDataNow; return nil }
            fed = true
            state.pointee = .haveData
            return input
        }
        if status == .error { throw AudioCodecError.encodeFailed(error?.localizedDescription ?? "unknown") }
        guard output.packetCount > 0, output.byteLength > 0 else { return nil }
        return [UInt8](UnsafeBufferPointer(start: output.data.assumingMemoryBound(to: UInt8.self), count: Int(output.byteLength)))
    }
}

/// Access unit AAC-ELD → PCM s16 stereo 48 kHz xen kẽ (512 mẫu/kênh). Không thread-safe.
public final class AacEldDecoder: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let compressed: AVAudioFormat
    private let pcm: AVAudioFormat

    public init() throws {
        guard let pcm = AacEldFormat.pcm, let compressed = AacEldFormat.compressed, let converter = AVAudioConverter(from: compressed, to: pcm)
        else { throw AudioCodecError.unavailable }
        (self.pcm, self.compressed, self.converter) = (pcm, compressed, converter)
    }

    public func decode(_ unit: [UInt8]) throws -> [Int16] {
        guard !unit.isEmpty, unit.count <= AudioPayload.maxUnitBytes else { throw AudioCodecError.decodeFailed("độ dài access unit \(unit.count)") }
        let input = AVAudioCompressedBuffer(format: compressed, packetCapacity: 1, maximumPacketSize: unit.count)
        unit.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress { input.data.copyMemory(from: base, byteCount: unit.count) }
        }
        input.byteLength = UInt32(unit.count)
        input.packetCount = 1
        input.packetDescriptions?[0] = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(unit.count))
        guard let output = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: AVAudioFrameCount(AudioPayload.aacFramesPerUnit * 2)),
              let channel = output.int16ChannelData?[0]
        else { throw AudioCodecError.decodeFailed("không cấp được bộ đệm") }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if fed { state.pointee = .noDataNow; return nil }
            fed = true
            state.pointee = .haveData
            return input
        }
        if status == .error { throw AudioCodecError.decodeFailed(error?.localizedDescription ?? "unknown") }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength) * AudioPayload.channels))
    }
}
