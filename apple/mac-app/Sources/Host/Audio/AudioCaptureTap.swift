import AudioToolbox
import CoreMedia
import Foundation

/// Đổi `CMSampleBuffer` âm thanh của ScreenCaptureKit (Float32, thường tách kênh) sang s16 xen kẽ L,R.
enum AudioCaptureTap {
    struct Converted {
        let samples: [Int16]
        /// Mẫu đầu tiên đã "già" bao lâu (ms) so với lúc nhận, tính trên đồng hồ máy (cùng đồng hồ với PTS của SCK).
        let ageMs: Double
    }

    static func convert(_ sample: CMSampleBuffer) -> Converted? {
        guard let format = CMSampleBufferGetFormatDescription(sample),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM, asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.mBitsPerChannel == 32, asbd.mChannelsPerFrame >= 1
        else { return nil }
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0 else { return nil }
        let planar = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let channels = Int(asbd.mChannelsPerFrame)
        let samples: [Int16]? = try? sample.withAudioBufferList { list, _ in
            interleave(list, frames: frames, channels: channels, planar: planar)
        }
        guard let samples else { return nil }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let ageMs = max(0, CMTimeGetSeconds(CMTimeSubtract(now, CMSampleBufferGetPresentationTimeStamp(sample))) * 1000)
        return Converted(samples: samples, ageMs: ageMs)
    }

    /// Luôn xuất đúng 2 kênh: mono nhân đôi, nhiều hơn 2 kênh lấy 2 kênh đầu.
    static func interleave(_ list: UnsafeMutableAudioBufferListPointer, frames: Int, channels: Int, planar: Bool) -> [Int16] {
        var out = [Int16](repeating: 0, count: frames * 2)
        func pointer(_ index: Int) -> UnsafePointer<Float>? {
            guard index < list.count, let data = list[index].mData else { return nil }
            return UnsafePointer(data.assumingMemoryBound(to: Float.self))
        }
        for channel in 0..<2 {
            let source = min(channel, channels - 1)
            if planar {
                guard let p = pointer(source), Int(list[source].mDataByteSize) >= frames * 4 else { continue }
                for i in 0..<frames { out[2 * i + channel] = clamp(p[i]) }
            } else {
                guard let p = pointer(0), Int(list[0].mDataByteSize) >= frames * channels * 4 else { continue }
                for i in 0..<frames { out[2 * i + channel] = clamp(p[i * channels + source]) }
            }
        }
        return out
    }

    private static func clamp(_ value: Float) -> Int16 {
        Int16(max(-1, min(1, value)) * Float(Int16.max))
    }
}
