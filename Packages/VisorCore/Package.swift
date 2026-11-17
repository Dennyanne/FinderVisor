// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VisorCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VisorCore", targets: ["VisorCore"]),
    ],
    targets: [
        .target(name: "VisorCore"),
        .testTarget(name: "VisorCoreTests", dependencies: ["VisorCore"]),
    ]
)
