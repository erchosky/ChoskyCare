// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChoskyCare",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ChoskyCare", targets: ["ChoskyCare"])
    ],
    targets: [
        .executableTarget(
            name: "ChoskyCare",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ChoskyCareTests",
            dependencies: ["ChoskyCare"]
        )
    ]
)
