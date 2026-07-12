// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuraPlayVideoEngine",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
        .visionOS("26.0"),
    ],
    products: [
        .library(
            name: "AuraPlayVideoEngine",
            targets: ["AuraPlayVideoEngine"]
        ),
        .executable(
            name: "AuraPlayVideoEngineDemo",
            targets: ["AuraPlayVideoEngineDemo"]
        ),
    ],
    dependencies: [
        .package(path: "../AuraPlayMediaCore"),
    ],
    targets: [
        .target(
            name: "AuraPlayVideoEngine",
            dependencies: ["AuraPlayMediaCore"],
            path: "Sources/AuraPlayVideoEngine"
        ),
        .executableTarget(
            name: "AuraPlayVideoEngineDemo",
            dependencies: ["AuraPlayVideoEngine"],
            path: "Examples/AuraPlayVideoEngineDemo"
        ),
        .testTarget(
            name: "AuraPlayVideoEngineTests",
            dependencies: ["AuraPlayVideoEngine"],
            path: "Tests/AuraPlayVideoEngineTests"
        ),
    ]
)
