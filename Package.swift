// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kadraj",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KadrajCore"),
        .executableTarget(name: "Kadraj", dependencies: ["KadrajCore"]),
        .testTarget(name: "KadrajCoreTests", dependencies: ["KadrajCore"]),
    ]
)
