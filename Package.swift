// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Pagecraft",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pagecraft", targets: ["Pagecraft"]),
        .library(name: "PagecraftCore", targets: ["PagecraftCore"]),
    ],
    targets: [
        .target(name: "PagecraftCore"),
        .executableTarget(name: "Pagecraft", dependencies: ["PagecraftCore"]),
        .testTarget(name: "PagecraftCoreTests", dependencies: ["PagecraftCore"]),
    ]
)
