// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DrumGateCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DrumGateCore",
            targets: ["DrumGateCore"]
        )
    ],
    targets: [
        .target(
            name: "DrumGateCore",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "DrumGateCoreTests",
            dependencies: ["DrumGateCore"],
            path: "Tests"
        )
    ]
)
