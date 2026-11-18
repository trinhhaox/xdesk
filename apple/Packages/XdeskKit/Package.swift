// swift-tools-version: 6.0
import PackageDescription

let modules = ["XdeskWire", "XdeskCrypto", "XdeskTransport", "XdeskMedia", "XdeskInput", "XdeskAgent"]
/// Phụ thuộc nội bộ giữa các module (Wire là nền, không phụ thuộc ai).
let moduleDependencies: [String: [String]] = [
    "XdeskTransport": ["XdeskWire"],
    "XdeskMedia": ["XdeskWire"],
]

let package = Package(
    name: "XdeskKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: modules.map { .library(name: $0, targets: [$0]) },
    targets: modules.flatMap { name in
        let deps = (moduleDependencies[name] ?? []).map { Target.Dependency.target(name: $0) }
        return [
            Target.target(name: name, dependencies: deps),
            Target.testTarget(
                name: "\(name)Tests",
                dependencies: [.target(name: name)] + deps
            ),
        ]
    }
)
