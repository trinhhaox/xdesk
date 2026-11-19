import AVFoundation
import SwiftUI
import XdeskCrypto
import XdeskViewer

/// "Quét mã QR trên Mac": camera + ô dán liên kết `xdesk://pair…` (dùng khi không có camera hoặc để thử).
struct PairWithMacView: View {
    let model: StreamViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var camera: CameraState = .checking
    @State private var pasted = ""
    @State private var problem: String?
    @State private var lastRejected: String?

    enum CameraState { case checking, ready, denied, missing }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    scanner
                } footer: {
                    Text("Trên Mac: menu Xdesk → \"Ghép đôi thiết bị mới…\", rồi hướng camera vào mã QR.")
                }
                Section("Hoặc dán liên kết ghép đôi") {
                    TextField("xdesk://pair?…", text: $pasted).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Ghép đôi") { accept(pasted) }.disabled(pasted.isEmpty)
                }
                if let problem { Section { Text(problem).foregroundStyle(BrandPalette.danger) } }
            }
            .navigationTitle("Quét mã QR trên Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Đóng") { dismiss() } }
            .task { camera = await Self.cameraState() }
        }
    }

    @ViewBuilder private var scanner: some View {
        switch camera {
        case .checking: ProgressView().frame(maxWidth: .infinity, minHeight: 280)
        case .ready:
            QrScannerView { accept($0) }
                .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(BrandPalette.primary, lineWidth: 3))
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Text("Xdesk cần quyền Camera để quét mã. Bật quyền trong Cài đặt, hoặc dán liên kết ở dưới.")
                Button("Mở Cài đặt") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            }
        case .missing: Text("Thiết bị này không có camera. Hãy dán liên kết ghép đôi ở dưới.")
        }
    }

    private func accept(_ text: String) {
        guard text != lastRejected else { return }
        switch PairingInput.parse(text) {
        case .success(let uri):
            dismiss()
            Task { await model.pair(with: uri) }
        case .failure(let error):
            lastRejected = text
            problem = error.localizedDescription
        }
    }

    private static func cameraState() async -> CameraState {
        guard AVCaptureDevice.default(for: .video) != nil else { return .missing }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .ready
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video) ? .ready : .denied
        default: return .denied
        }
    }
}
