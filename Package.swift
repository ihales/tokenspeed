// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenSpeed",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TokenSpeed", targets: ["TokenSpeed"])],
    targets: [
        .executableTarget(name: "TokenSpeed"),
        .testTarget(name: "TokenSpeedTests", dependencies: ["TokenSpeed"])
    ]
)
