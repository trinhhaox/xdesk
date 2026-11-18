import XdeskWire

/// Access unit đã phân tích: NAL dữ liệu ở dạng AVCC 4 byte + tham số (nếu có mặt trong AU).
public struct ParsedAccessUnit: Sendable, Equatable {
    public let avcc: [UInt8]
    public let parameterSets: [[UInt8]]
    public let containsKeyframe: Bool
}

/// Phân tích access unit Annex B (từ bộ ghép UDP) thành AVCC + tham số. Logic thuần.
public struct FrameAssembler: Sendable {
    public let codec: VideoCodec

    public init(codec: VideoCodec) { self.codec = codec }

    public func parse(annexB: [UInt8]) throws -> ParsedAccessUnit {
        let nals = AnnexB.splitNALUnits(annexB)
        guard !nals.isEmpty else { throw MediaError.malformedNAL("no start code") }
        let sets = nals.filter { AnnexB.isParameterSet($0, codec: codec) }
        let slices = nals.filter { !AnnexB.isParameterSet($0, codec: codec) }
        guard !slices.isEmpty else { throw MediaError.malformedNAL("no slice NAL") }
        return ParsedAccessUnit(
            avcc: AnnexB.toAVCC(slices), parameterSets: sets, containsKeyframe: slices.contains(where: isKeyframeSlice)
        )
    }

    private func isKeyframeSlice(_ nal: [UInt8]) -> Bool {
        guard let first = nal.first else { return false }
        switch codec {
        case .h264: return first & 0x1F == 5
        case .hevc: return (16...21).contains((first >> 1) & 0x3F)
        }
    }
}
