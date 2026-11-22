import Testing
import XdeskCrypto
@testable import Xdesk

struct HostFileGateTests {
    @Test func gateIsClosedUntilPermissionIsGranted() {
        let gate = HostFileGate()
        #expect(!gate.allowed)
        gate.set(DevicePermissions.default.fileTransfer)
        #expect(!gate.allowed)
        gate.set(true)
        #expect(gate.allowed)
        gate.set(false)
        #expect(!gate.allowed)
    }

    @Test func fileTransferPermissionIsIndependentOfInput() {
        let withInputOnly = DevicePermissions(view: true, input: true, clipboard: false, audio: false)
        #expect(!withInputOnly.fileTransfer)
        let withFilesOnly = DevicePermissions(view: true, input: false, clipboard: false, audio: false, fileTransfer: true)
        #expect(withFilesOnly.fileTransfer && !withFilesOnly.input)
    }

    @Test func authenticatedPeerWithoutRecordLosesAllPermissionsFailClosed() {
        let granted = DevicePermissions(view: true, input: true, clipboard: true, audio: true, unlock: true, fileTransfer: true)
        let key: [UInt8] = [1, 2, 3]
        // Thiết bị bị thu hồi/xoá: tra danh sách ra nil dù lúc bắt tay đã có quyền.
        let revoked = LivePermissions.resolve(peerKey: key, live: nil, snapshot: granted)
        #expect(!revoked.fileTransfer && !revoked.clipboard && !revoked.unlock && !revoked.input)
        // Còn trong danh sách: dùng quyền sống, không dùng snapshot.
        let off = DevicePermissions(view: true, input: true, clipboard: false, audio: false)
        #expect(!LivePermissions.resolve(peerKey: key, live: off, snapshot: granted).fileTransfer)
        // Không có peer xác thực (Debug plaintext): dùng quyền lúc bắt tay.
        #expect(LivePermissions.resolve(peerKey: nil, live: nil, snapshot: granted).fileTransfer)
    }
}
