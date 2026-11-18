// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "gen-test-vectors",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../apple/Packages/XdeskKit")],
    targets: [
        .executableTarget(
            name: "gen-test-vectors",
            dependencies: [.product(name: "XdeskWire", package: "XdeskKit")]
        ),
    ]
)
