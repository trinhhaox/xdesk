import XdeskTransport
import XdeskViewer

extension StreamViewModel {
    /// Bật cổng USB (chỉ khi app ở foreground; iOS tự treo listener khi vào nền nên bật lại ở `.active`).
    func startUsbListener() {
        if usbListener == nil {
            usbListener = UsbListener { [weak self] tunnel in await self?.acceptUsb(tunnel) }
        }
        usbListener?.start()
    }

    func stopUsbListener() { usbListener?.stop() }

    /// Mac vừa nối qua cáp: bắt tay (IK với khoá host đã ghép, Noise như Wi-Fi) rồi mới chuyển sang màn hình stream.
    /// Lỗi (host lạ, bị thu hồi…) chỉ hiện thông báo ở danh sách, không đổi màn hình.
    func acceptUsb(_ tunnel: ControlConnection) async {
        guard !inStream, session.state == .idle, let metrics = ScreenMetrics.current(), let config = plan(metrics) else {
            await tunnel.close()
            return
        }
        errorMessage = nil
        currentConfig = config
        await session.connect(tunnel: tunnel, config: config)
        guard case .streaming = session.state else {
            if case .failed(let message) = session.state { errorMessage = "USB: \(message)" }
            await session.disconnect()
            return
        }
        inStream = true
        await refreshTrust()
    }
}
