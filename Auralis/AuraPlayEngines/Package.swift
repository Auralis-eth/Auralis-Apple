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
        .library(name: "AuraPlayEngines", targets: ["AuraPlayEngines"]),
        // The two demo apps are the package's only non-library targets. They are executables rather
        // than another framework, and they exist to exercise the engine API outside the app.
        .executable(name: "AuraPlayAudioEngineDemo", targets: ["AuraPlayAudioEngineDemo"]),
        .executable(name: "AuraPlayVideoEngineDemo", targets: ["AuraPlayVideoEngineDemo"])
    ],
    targets: [
        .target(name: "AuraPlayEngines"),
        .executableTarget(
            name: "AuraPlayAudioEngineDemo",
            dependencies: ["AuraPlayEngines"],
            path: "Examples/AuraPlayAudioEngineDemo"
        ),
        .executableTarget(
            name: "AuraPlayVideoEngineDemo",
            dependencies: ["AuraPlayEngines"],
            path: "Examples/AuraPlayVideoEngineDemo"
        ),
        .testTarget(
            name: "AuraPlayEnginesTests",
            dependencies: ["AuraPlayEngines"],
            resources: [.process("AudioEngine/Fixtures")]
        )
    ]
)
