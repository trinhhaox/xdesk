import XdeskViewer

extension StreamViewModel {
    /// Tên người đọc được của đích: tên Bonjour, tên host đã lưu, hoặc `host:port`.
    func displayName(of target: ViewerTarget) -> String {
        switch target {
        case .discovered(let host): host.name
        case .manual(let host, let port):
            knownHosts.first { $0.role == .host && $0.lastAddress == "\(host):\(port)" }?.name
                ?? manualHosts.first { ViewerTarget.parse(manual: $0.address) == target }?.name ?? "\(host):\(port)"
        }
    }

    /// Kết nối lại đích gần nhất (nút "Thử lại" trên thẻ lỗi).
    func retryLast() async {
        guard let target else { return }
        await connect(to: target)
    }
}
