import AppKit

// latency-probe clock [--display-name Xdesk] [--seconds 60]
//   Cửa sổ trên màn hình ảo: đồng hồ ms + mã 32 bit (xem README.md).
// latency-probe measure <ảnh.png>...
//   Giải mã vạch tím (probe trong video) và vạch xanh (lớp phủ viewer) → độ trễ từng ảnh, rồi p50/p95.

let args = Array(CommandLine.arguments.dropFirst())

func option(_ name: String, default fallback: String) -> String {
    guard let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return fallback }
    return args[i + 1]
}

@MainActor func runClock() {
    let name = option("--display-name", default: "Xdesk")
    let seconds = Double(option("--seconds", default: "60")) ?? 60
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    guard let screen = NSScreen.screens.first(where: { $0.localizedName == name }) else {
        FileHandle.standardError.write(Data("Không thấy màn hình tên \"\(name)\". Hãy bật host Xdesk trước.\n".utf8))
        exit(2)
    }
    let window = ClockWindow(screen: screen)
    window.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApplication.shared.terminate(nil) }
    app.run()
}

switch args.first {
case "clock":
    MainActor.assumeIsolated { runClock() }
case "measure" where args.count > 1:
    exit(measure(paths: Array(args.dropFirst())))
default:
    print("Dùng: latency-probe clock [--display-name Xdesk] [--seconds 60] | latency-probe measure <ảnh.png>...")
    exit(64)
}
