import SwiftUI
import XdeskCrypto

extension View {
    /// Hộp thoại xác nhận "Xoá <tên>?" dùng chung cho màn chính và Cài đặt › Bảo mật.
    func forgetHostDialog(_ device: Binding<PairedDevice?>, model: StreamViewModel) -> some View {
        confirmationDialog(
            "Xoá \(device.wrappedValue?.name ?? "")?",
            isPresented: Binding(get: { device.wrappedValue != nil }, set: { if !$0 { device.wrappedValue = nil } }),
            titleVisibility: .visible, presenting: device.wrappedValue
        ) { host in
            Button("Xoá máy này", role: .destructive) { Task { await model.forget(host) } }
        } message: { _ in
            Text("Điện thoại sẽ không tự kết nối tới máy này nữa. Muốn dùng lại phải ghép đôi lại. (Trên Mac, thiết bị này vẫn có trong danh sách cho tới khi bạn thu hồi.)")
        }
    }
}
