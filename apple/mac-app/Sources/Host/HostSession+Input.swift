import Foundation
import XdeskTransport
import XdeskWire

extension HostSession {
    func startInput(displayID: CGDirectDisplayID) async {
        let service = HostInputService(
            streamId: Self.streamId, mapper: CoordinateMapper(displayID: displayID), onSecureInput: onSecureInput
        )
        input = service
        await service.start()
    }

    /// Chỉ nhận input khi viewer đã báo địa chỉ UDP (phiên đang streaming); trước đó bỏ qua.
    func handleInputPacket(_ packet: MediaPacket) async {
        guard viewerReady, let ack = await input?.handle(packet), let channel else { return }
        do { try await channel.sendPacket(ack) } catch {
            log.error("gửi input-ack lỗi: \(error.localizedDescription, privacy: .public)")
        }
    }

    func handleInputText(_ text: String) async {
        guard viewerReady else { return }
        await input?.typeText(text)
    }
}
