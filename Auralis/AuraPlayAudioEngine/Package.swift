// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuraPlayAudioEngine",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
    ],
    products: [
        .library(
            name: "AuraPlayAudioEngine",
            targets: ["AuraPlayAudioEngine"]
        ),
        .executable(
            name: "AuraPlayAudioEngineDemo",
            targets: ["AuraPlayAudioEngineDemo"]
        ),
    ],
    dependencies: [
        .package(path: "../AuraPlayMediaCore"),
    ],
    targets: [
        .target(
            name: "AuraPlayAudioEngine",
            dependencies: ["AuraPlayMediaCore"],
            path: "Sources/AuraPlayAudioEngine"
        ),
        .executableTarget(
            name: "AuraPlayAudioEngineDemo",
            dependencies: ["AuraPlayAudioEngine"],
            path: "Examples/AuraPlayAudioEngineDemo"
        ),
        .testTarget(
            name: "AuraPlayAudioEngineTests",
            dependencies: ["AuraPlayAudioEngine"],
            path: "Tests/AuraPlayAudioEngineTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
