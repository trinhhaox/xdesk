import AppKit
import Foundation

private struct Marker {
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    var isFound: Bool { maxX >= 0 && maxX - minX >= 6 }
}

private struct Pixels {
    let width: Int, height: Int, data: [UInt8]

    init?(path: String) {
        guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = image.width, h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        width = w
        height = h
        data = buffer
    }

    func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    /// Vạch dài nhất (đoạn ngang liên tục dài nhất thoả `match`) rồi mở rộng theo chiều dọc: bỏ qua điểm lẻ cùng màu ở nơi khác.
    func bounds(where match: (Int, Int, Int) -> Bool) -> Marker {
        var best = (len: 0, start: 0, y: 0)
        for y in 0..<height {
            var start = 0, run = 0
            for x in 0..<width {
                let (r, g, b) = rgb(x, y)
                if match(r, g, b) {
                    if run == 0 { start = x }
                    run += 1
                    if run > best.len { best = (run, start, y) }
                } else { run = 0 }
            }
        }
        var marker = Marker()
        guard best.len >= 6 else { return marker }
        let cx = best.start + best.len / 2
        var top = best.y, bottom = best.y
        while top > 0, matches(cx, top - 1, match) { top -= 1 }
        while bottom < height - 1, matches(cx, bottom + 1, match) { bottom += 1 }
        marker.minX = best.start; marker.maxX = best.start + best.len - 1
        marker.minY = top; marker.maxY = bottom
        return marker
    }

    private func matches(_ x: Int, _ y: Int, _ match: (Int, Int, Int) -> Bool) -> Bool {
        let (r, g, b) = rgb(x, y)
        return match(r, g, b)
    }

    /// Đọc 32 bit: marker rộng 2 ô; bit 0 bắt đầu sau 1 ô trống.
    func decode(_ m: Marker) -> UInt32? {
        let cell = Double(m.maxX - m.minX + 1) / 2
        let y = (m.minY + m.maxY) / 2
        var code: UInt32 = 0
        for bit in 0..<32 {
            let x = Int(Double(m.minX) + cell * (3 + Double(bit) + 0.5))
            guard x < width, y < height else { return nil }
            let (r, g, b) = rgb(x, y)
            code = (code << 1) | ((r + g + b) / 3 > 127 ? 1 : 0)
        }
        return code
    }
}

/// Trả mã thoát: 0 nếu có ít nhất một mẫu hợp lệ.
func measure(paths: [String]) -> Int32 {
    var latencies: [Int64] = []
    for path in paths {
        guard let pixels = Pixels(path: path) else { print("\(path): không đọc được ảnh"); continue }
        let probe = pixels.bounds { r, g, b in r > 170 && b > 170 && g < 100 }
        let overlay = pixels.bounds { r, g, b in g > 170 && r < 100 && b < 100 }
        guard probe.isFound, overlay.isFound, let probeCode = pixels.decode(probe), let overlayCode = pixels.decode(overlay) else {
            print("\(path): không thấy đủ hai vạch (probe=\(probe.isFound), overlay=\(overlay.isFound))")
            continue
        }
        let delta = Int64(Int32(bitPattern: overlayCode &- probeCode))
        print("\(path): overlay-probe = \(delta) ms")
        if (0..<2000).contains(delta) { latencies.append(delta) }
    }
    guard !latencies.isEmpty else { print("Không có mẫu hợp lệ"); return 1 }
    let sorted = latencies.sorted()
    func pct(_ p: Double) -> Int64 { sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
    print("n=\(sorted.count) min=\(sorted[0]) p50=\(pct(0.5)) p95=\(pct(0.95)) max=\(sorted[sorted.count - 1]) (ms)")
    return 0
}
