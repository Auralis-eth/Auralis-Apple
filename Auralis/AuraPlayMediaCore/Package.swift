// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuraPlayMediaCore",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
        .visionOS("26.0"),
    ],
    products: [
        .library(
            name: "AuraPlayMediaCore",
            targets: ["AuraPlayMediaCore"]
        ),
    ],
    targets: [
        .target(
            name: "AuraPlayMediaCore",
            path: "Sources/AuraPlayMediaCore"
        ),
        .testTarget(
            name: "AuraPlayMediaCoreTests",
            dependencies: ["AuraPlayMediaCore"],
            path: "Tests/AuraPlayMediaCoreTests"
        ),
    ]
)
