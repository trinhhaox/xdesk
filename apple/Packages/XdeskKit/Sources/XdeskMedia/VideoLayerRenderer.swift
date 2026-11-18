import AVFoundation
import CoreMedia

/// Vẽ `CMSampleBuffer` lên `AVSampleBufferDisplayLayer` (giải mã phần cứng, hiển thị ngay không chờ PTS).
/// Gắn `layer` vào view; lỗi renderer (vd. sau khi app nền) được flush tự động ở lần enqueue kế tiếp.
@MainActor
public final class VideoLayerRenderer {
    public let layer = AVSampleBufferDisplayLayer()

    public init() {
        layer.videoGravity = .resizeAspect
    }

    /// `true` nếu đã đưa vào hàng đợi; `false` nếu renderer đang lỗi và vừa được flush (khung này bị bỏ,
    /// người gọi nên xin keyframe).
    @discardableResult
    public func enqueue(_ sample: CMSampleBuffer) -> Bool {
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed {
            renderer.flush()
            return false
        }
        renderer.enqueue(sample)
        return true
    }

    public func flush() { layer.sampleBufferRenderer.flush() }
}
