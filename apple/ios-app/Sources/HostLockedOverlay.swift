import SwiftUI
import XdeskViewer
import XdeskWire

/// Phủ lên video khi host báo Mac đang khoá/tắt màn hình (`host.state videoAvailable:false`): phiên vẫn sống nhưng chưa có hình.
/// Nút "Mở khoá Mac" nằm ngay đây (không phải mở menu nổi) cùng nút Ngắt kết nối.
struct HostLockedOverlay: View {
    let session: ViewerSession
    let onDisconnect: () -> Void
    @State private var resultMessage: String?
    @State private var resultTask: Task<Void, Never>?

    private var title: String {
        session.hostState?.locked == true ? "Mac đang khoá" : "Màn hình Mac đang tắt"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.display").font(.system(size: 40)).foregroundStyle(.white)
            Text(title).font(.headline)
            Text("Bấm Mở khoá Mac để đánh thức và mở khoá. Hình sẽ hiện lại khi Mac mở khoá.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
            Button { Task { await session.sendSystemUnlock() } } label: {
                Label("Mở khoá Mac", systemImage: "faceid").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandPalette.primaryFill)
            .accessibilityIdentifier("host-locked-unlock")
            if let resultMessage {
                Text(resultMessage).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.white)
            }
            Button(role: .destructive, action: onDisconnect) {
                Text("Ngắt kết nối").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: 360)
        .background(BrandPalette.overlaySurface.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.75).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .onChange(of: session.lastUnlockResult) { _, result in
            guard let result else { return }
            resultTask?.cancel()
            resultMessage = result.message
            resultTask = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                resultMessage = nil
            }
        }
    }
}
