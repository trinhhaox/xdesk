import Foundation
import XdeskTransport

/// Ảnh chụp dữ liệu popover (thuần giá trị) để view vẽ được cả với dữ liệu giả khi kiểm tra giao diện.
struct PopoverState: Equatable {
    struct Session: Equatable, Identifiable {
        let id: UUID
        let info: ViewerSessionInfo
    }

    struct Usb: Equatable, Identifiable {
        let id: Int
        let label: String
    }

    var pill: StatusPill = .stopped
    var isHosting = false
    var errorMessage: String?
    var missing: [PermissionKind] = []
    var sessions: [Session] = []
    var lanText: String?
    var tailscaleText = String(localized: "Tailscale: tắt")
    var usb: [Usb] = []
    var usbMessage: String?
    var secureInput = false
    var updateVersion: String?
    var canCheckUpdates = true
    /// Phiên bản đang chạy, hiện cạnh tên app ở đầu popover.
    var version: String?
    var activeTransfer: FileTransferProgress?
    var receivedFile: FileTransferCompletion?
    var transferError: String?
}

/// Hành động người dùng trong popover; mặc định không làm gì (dùng cho ảnh chụp giao diện).
struct PopoverActions {
    var toggleSharing: () -> Void = {}
    var disconnect: (UUID) -> Void = { _ in }
    var sendFile: (UUID) -> Void = { _ in }
    var cancelTransfer: () -> Void = {}
    var revealFile: (URL) -> Void = { _ in }
    var dismissFileNotice: () -> Void = {}
    var openPermission: (PermissionKind) -> Void = { _ in }
    var pairNewDevice: () -> Void = {}
    var showPairedDevices: () -> Void = {}
    var connectToMac: () -> Void = {}
    var connectUsb: (Int) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var checkForUpdates: () -> Void = {}
    var quit: () -> Void = {}
    /// Mở lại Xdesk: macOS chỉ áp quyền Ghi màn hình mới cấp sau khi app khởi động lại.
    var relaunch: () -> Void = {}
}
