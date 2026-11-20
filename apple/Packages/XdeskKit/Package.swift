// swift-tools-version: 6.0
import PackageDescription

let modules = ["XdeskWire", "XdeskCrypto", "XdeskTransport", "XdeskMedia", "XdeskViewer", "XdeskInput", "XdeskAgent", "XdeskClipboard"]
/// Phụ thuộc nội bộ giữa các module (Wire là nền, không phụ thuộc ai).
let moduleDependencies: [String: [String]] = [
    "XdeskTransport": ["XdeskWire", "XdeskCrypto"],
    "XdeskMedia": ["XdeskWire"],
    "XdeskInput": ["XdeskWire"],
    "XdeskClipboard": ["XdeskWire", "XdeskTransport"],
    "XdeskViewer": ["XdeskWire", "XdeskCrypto", "XdeskTransport", "XdeskMedia", "XdeskInput", "XdeskClipboard"],
]

/// Module có chuỗi hiển thị cho người dùng (Resources/Localizable.xcstrings: nguồn "vi" + bản dịch "en").
/// XdeskAgent cố ý không có: chuỗi của nó dành cho AI agent/MCP client, không phải người dùng.
let localizedModules: Set<String> = ["XdeskTransport", "XdeskViewer"]

let package = Package(
    name: "XdeskKit",
    defaultLocalization: "vi",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: modules.map { .library(name: $0, targets: [$0]) },
    targets: modules.flatMap { name in
        let deps = (moduleDependencies[name] ?? []).map { Target.Dependency.target(name: $0) }
        return [
            Target.target(
                name: name,
                dependencies: deps,
                resources: localizedModules.contains(name) ? [.process("Resources")] : []
            ),
            Target.testTarget(
                name: "\(name)Tests",
                dependencies: [.target(name: name)] + deps
            ),
        ]
    }
)
