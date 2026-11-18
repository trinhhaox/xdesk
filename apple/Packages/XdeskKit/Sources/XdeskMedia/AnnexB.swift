import XdeskWire

/// Chuyển đổi NAL giữa AVCC (độ dài 1–4 byte đứng trước) và Annex B (start code `00 00 00 01`). Hàm thuần.
public enum AnnexB {
    public static let startCode: [UInt8] = [0, 0, 0, 1]

    /// AVCC → Annex B. Độ dài NAL vượt dữ liệu hoặc bằng 0 → `malformedNAL`.
    public static func fromAVCC(_ avcc: [UInt8], lengthSize: Int) throws -> [UInt8] {
        guard (1...4).contains(lengthSize) else { throw MediaError.malformedNAL("length size \(lengthSize)") }
        var out: [UInt8] = []
        out.reserveCapacity(avcc.count + 16)
        var i = 0
        while i < avcc.count {
            guard i + lengthSize <= avcc.count else { throw MediaError.malformedNAL("truncated length") }
            let len = avcc[i..<i + lengthSize].reduce(0) { ($0 << 8) | Int($1) }
            i += lengthSize
            guard len > 0, i + len <= avcc.count else { throw MediaError.malformedNAL("nal length \(len)") }
            out += startCode
            out += avcc[i..<i + len]
            i += len
        }
        return out
    }

    /// Tách các NAL (không kèm start code) từ dòng Annex B; chấp nhận start code 3 hoặc 4 byte.
    public static func splitNALUnits(_ data: [UInt8]) -> [[UInt8]] {
        var starts: [(code: Int, payload: Int)] = []
        var i = 0
        while i + 3 <= data.count {
            if data[i] == 0, data[i + 1] == 0, data[i + 2] == 1 {
                let codeStart = (i > 0 && data[i - 1] == 0) ? i - 1 : i
                starts.append((codeStart, i + 3))
                i += 3
            } else {
                i += 1
            }
        }
        return starts.enumerated().compactMap { idx, s in
            let end = idx + 1 < starts.count ? starts[idx + 1].code : data.count
            return end > s.payload ? Array(data[s.payload..<end]) : nil
        }
    }

    /// NAL → AVCC với độ dài 4 byte.
    public static func toAVCC(_ nals: [[UInt8]]) -> [UInt8] {
        var out: [UInt8] = []
        for nal in nals {
            let n = UInt32(nal.count)
            out += [UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
            out += nal
        }
        return out
    }

    public static func fromParameterSets(_ sets: [[UInt8]]) -> [UInt8] { sets.flatMap { startCode + $0 } }

    public static func isParameterSet(_ nal: [UInt8], codec: VideoCodec) -> Bool {
        guard let first = nal.first else { return false }
        switch codec {
        case .h264: return [7, 8].contains(first & 0x1F)
        case .hevc: return [32, 33, 34].contains((first >> 1) & 0x3F)
        }
    }
}
