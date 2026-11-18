import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

enum CaptureError: Error, LocalizedError, Equatable {
    case permissionDenied
    case displayNotFound(CGDirectDisplayID)

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Chưa có quyền Ghi màn hình. \(PermissionsCheck.settingsHint)"
        case .displayNotFound(let id): "Không tìm thấy màn hình \(id) để capture"
        }
    }
}

/// `CVPixelBuffer` đi qua ranh giới đồng thời (SCK → encoder); buffer chỉ đọc sau khi giao.
struct CapturedFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
}

/// SCStream cho đúng một màn hình: 420v (khớp encoder), queueDepth 3, con trỏ nằm trong ảnh.
/// SCK chỉ phát khung khi nội dung đổi nên màn tĩnh tốn ~0 băng thông.
final class CaptureService: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private static let lookupAttempts = 15
    private let displayID: CGDirectDisplayID
    private let width: Int
    private let height: Int
    private let fps: Int
    private let onFrame: @Sendable (CapturedFrame) -> Void
    private let onStop: @Sendable (Error?) -> Void
    private let sampleQueue = DispatchQueue(label: "xdesk.capture.samples", qos: .userInteractive)
    private let lock = NSLock()
    private var stream: SCStream?
    private var stopping = false

    init(
        displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int,
        onFrame: @escaping @Sendable (CapturedFrame) -> Void, onStop: @escaping @Sendable (Error?) -> Void
    ) {
        self.displayID = displayID
        self.width = width
        self.height = height
        self.fps = fps
        self.onFrame = onFrame
        self.onStop = onStop
    }

    func start() async throws {
        guard PermissionsCheck.hasScreenRecording else {
            PermissionsCheck.requestScreenRecording()
            throw CaptureError.permissionDenied
        }
        let display = try await findDisplay()
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.queueDepth = 3
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.showsCursor = true
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()
        lock.withLock { self.stream = stream }
    }

    func stop() async {
        let active: SCStream? = lock.withLock {
            stopping = true
            defer { stream = nil }
            return stream
        }
        do { try await active?.stopCapture() } catch { onStop(error) }
    }

    /// Màn hình ảo mới tạo có thể chưa xuất hiện trong danh sách SCK ngay → thử lại tối đa ~3 s.
    private func findDisplay() async throws -> SCDisplay {
        for attempt in 0..<Self.lookupAttempts {
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                throw CaptureError.permissionDenied
            }
            if let display = content.displays.first(where: { $0.displayID == displayID }) { return display }
            if attempt < Self.lookupAttempts - 1 { try await Task.sleep(for: .milliseconds(200)) }
        }
        throw CaptureError.displayNotFound(displayID)
    }

    // MARK: SCStreamOutput / SCStreamDelegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, let pixelBuffer = sampleBuffer.imageBuffer, Self.isCompleteFrame(sampleBuffer) else { return }
        onFrame(CapturedFrame(pixelBuffer: pixelBuffer))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let intentional = lock.withLock { stopping }
        if !intentional { onStop(error) }
    }

    private static func isCompleteFrame(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}
