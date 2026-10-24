// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ArtifactCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ArtifactCore",
            targets: ["ArtifactCore"]
        )
    ],
    dependencies: [
        .package(path: "../RuntimeCore")
    ],
    targets: [
        .target(
            name: "ArtifactCore",
            dependencies: [
                "RuntimeCore"
            ]
        ),
        .testTarget(
            name: "ArtifactCoreTests",
            dependencies: ["ArtifactCore"]
        )
    ]
)
