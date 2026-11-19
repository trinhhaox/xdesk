import AudioToolbox
import Foundation
import Testing
@testable import Xdesk

@Suite struct AudioCaptureTapTests {
    private func withList<T>(buffers: [[Float]], interleavedChannels: Int?, _ body: (UnsafeMutableAudioBufferListPointer) -> T) -> T {
        let pointers = buffers.map { values -> UnsafeMutablePointer<Float> in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: max(values.count, 1))
            pointer.initialize(from: values, count: values.count)
            return pointer
        }
        defer { pointers.forEach { $0.deallocate() } }
        let list = AudioBufferList.allocate(maximumBuffers: buffers.count)
        defer { free(list.unsafeMutablePointer) }
        for (index, values) in buffers.enumerated() {
            list[index] = AudioBuffer(
                mNumberChannels: UInt32(interleavedChannels ?? 1), mDataByteSize: UInt32(values.count * 4), mData: UnsafeMutableRawPointer(pointers[index]))
        }
        return body(list)
    }

    @Test func planarFloatBecomesInterleavedInt16() {
        let out = withList(buffers: [[1, 0.5, -1], [0, -0.5, 2]], interleavedChannels: nil) {
            AudioCaptureTap.interleave($0, frames: 3, channels: 2, planar: true)
        }
        #expect(out == [32767, 0, 16383, -16383, -32767, 32767])
    }

    @Test func interleavedFloatKeepsChannelOrder() {
        let out = withList(buffers: [[0.25, -0.25, 0.5, -0.5]], interleavedChannels: 2) {
            AudioCaptureTap.interleave($0, frames: 2, channels: 2, planar: false)
        }
        #expect(out == [8191, -8191, 16383, -16383])
    }

    @Test func monoIsDuplicatedAndShortBuffersAreSilence() {
        let mono = withList(buffers: [[0.5, -0.5]], interleavedChannels: nil) {
            AudioCaptureTap.interleave($0, frames: 2, channels: 1, planar: true)
        }
        #expect(mono == [16383, 16383, -16383, -16383])
        let short = withList(buffers: [[0.5], [0.5]], interleavedChannels: nil) {
            AudioCaptureTap.interleave($0, frames: 4, channels: 2, planar: true)
        }
        #expect(short == [Int16](repeating: 0, count: 8), "buffer ngắn hơn số khung khai báo không được đọc quá biên")
    }
}
