import AVFoundation
import SwiftUI

/// Khung camera quét mã QR; mỗi chuỗi đọc được gọi `onCode` (nơi gọi tự lọc trùng/sai định dạng).
struct QrScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController { ScannerController(onCode: onCode) }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

/// Chạy/dừng `AVCaptureSession` trên hàng đợi riêng (`startRunning` chặn luồng gọi).
private final class SessionRunner: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "xdesk.qr-scanner")

    func start() { queue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let runner = SessionRunner()
    private let onCode: (String) -> Void
    private var preview: AVCaptureVideoPreviewLayer?

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
              runner.session.canAddInput(input) else { return }
        runner.session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard runner.session.canAddOutput(output) else { return }
        runner.session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: runner.session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        runner.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        runner.stop()
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let values = objects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        guard let first = values.first else { return }
        MainActor.assumeIsolated { onCode(first) }
    }
}
