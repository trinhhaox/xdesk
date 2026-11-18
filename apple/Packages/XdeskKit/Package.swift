// swift-tools-version: 6.0
import PackageDescription

let modules = ["XdeskWire", "XdeskCrypto", "XdeskTransport", "XdeskMedia", "XdeskInput", "XdeskAgent"]

let package = Package(
    name: "XdeskKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: modules.map { .library(name: $0, targets: [$0]) },
    targets: modules.flatMap { name in
        [
            Target.target(name: name),
            Target.testTarget(name: "\(name)Tests", dependencies: [.target(name: name)]),
        ]
    }
)
