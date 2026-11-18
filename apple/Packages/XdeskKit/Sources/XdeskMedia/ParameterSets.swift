import CoreMedia
import XdeskWire

/// Trích/dựng tham số (SPS/PPS, VPS/SPS/PPS cho HEVC) từ/vào `CMFormatDescription`.
enum ParameterSets {
    /// Danh sách tham số + độ dài trường NAL của AVCC.
    static func extract(from fd: CMFormatDescription, codec: VideoCodec) throws -> (sets: [[UInt8]], lengthSize: Int) {
        var count = 0
        var lengthSize: Int32 = 0
        func read(_ index: Int) -> (ptr: UnsafePointer<UInt8>?, size: Int, status: OSStatus) {
            var ptr: UnsafePointer<UInt8>?
            var size = 0
            let status: OSStatus = switch codec {
            case .h264: CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fd, parameterSetIndex: index, parameterSetPointerOut: &ptr, parameterSetSizeOut: &size, parameterSetCountOut: &count, nalUnitHeaderLengthOut: &lengthSize)
            case .hevc: CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(fd, parameterSetIndex: index, parameterSetPointerOut: &ptr, parameterSetSizeOut: &size, parameterSetCountOut: &count, nalUnitHeaderLengthOut: &lengthSize)
            }
            return (ptr, size, status)
        }
        let first = read(0)
        guard first.status == noErr else { throw MediaError.formatDescriptionFailed(first.status) }
        var sets: [[UInt8]] = []
        for index in 0..<count {
            let item = read(index)
            guard item.status == noErr, let ptr = item.ptr else { throw MediaError.formatDescriptionFailed(item.status) }
            sets.append(Array(UnsafeBufferPointer(start: ptr, count: item.size)))
        }
        return (sets, Int(lengthSize))
    }

    /// Dựng `CMVideoFormatDescription` (NAL header 4 byte) từ tham số.
    static func makeFormatDescription(_ sets: [[UInt8]], codec: VideoCodec) throws -> CMVideoFormatDescription {
        guard !sets.isEmpty else { throw MediaError.missingParameterSets }
        let flat = sets.flatMap { $0 }
        var offsets: [Int] = []
        var running = 0
        for set in sets { offsets.append(running); running += set.count }
        let sizes = sets.map(\.count)
        var fd: CMVideoFormatDescription?
        let status: OSStatus = flat.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return kCMFormatDescriptionBridgeError_InvalidParameter }
            let pointers = offsets.map { base + $0 }
            return pointers.withUnsafeBufferPointer { pp in
                sizes.withUnsafeBufferPointer { sp in
                    guard let ptrs = pp.baseAddress, let szs = sp.baseAddress else { return kCMFormatDescriptionBridgeError_InvalidParameter }
                    return switch codec {
                    case .h264:
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: sets.count, parameterSetPointers: ptrs, parameterSetSizes: szs, nalUnitHeaderLength: 4, formatDescriptionOut: &fd)
                    case .hevc:
                        CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: nil, parameterSetCount: sets.count, parameterSetPointers: ptrs, parameterSetSizes: szs, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &fd)
                    }
                }
            }
        }
        guard status == noErr, let fd else { throw MediaError.formatDescriptionFailed(status) }
        return fd
    }
}
