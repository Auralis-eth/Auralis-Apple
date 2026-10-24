// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AuraPlayEngines",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
        .visionOS("26.0")
    ],
    products: [
        .library(name: "AuraPlayMediaCore", targets: ["AuraPlayMediaCore"]),
        .library(name: "AuraPlayAudioEngine", targets: ["AuraPlayAudioEngine"]),
        .library(name: "AuraPlayVideoEngine", targets: ["AuraPlayVideoEngine"]),
        .executable(name: "AuraPlayAudioEngineDemo", targets: ["AuraPlayAudioEngineDemo"]),
        .executable(name: "AuraPlayVideoEngineDemo", targets: ["AuraPlayVideoEngineDemo"])
    ],
    targets: [
        .target(name: "AuraPlayMediaCore"),
        .target(
            name: "AuraPlayAudioEngine",
            dependencies: ["AuraPlayMediaCore"]
        ),
        .target(
            name: "AuraPlayVideoEngine",
            dependencies: ["AuraPlayMediaCore"]
        ),
        .executableTarget(
            name: "AuraPlayAudioEngineDemo",
            dependencies: ["AuraPlayAudioEngine"],
            path: "Examples/AuraPlayAudioEngineDemo"
        ),
        .executableTarget(
            name: "AuraPlayVideoEngineDemo",
            dependencies: ["AuraPlayVideoEngine"],
            path: "Examples/AuraPlayVideoEngineDemo"
        ),
        .testTarget(
            name: "AuraPlayMediaCoreTests",
            dependencies: ["AuraPlayMediaCore"]
        ),
        .testTarget(
            name: "AuraPlayAudioEngineTests",
            dependencies: ["AuraPlayAudioEngine"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "AuraPlayVideoEngineTests",
            dependencies: ["AuraPlayVideoEngine"]
        )
    ]
)
