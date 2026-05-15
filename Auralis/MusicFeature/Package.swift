// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MusicFeature",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "MusicFeature",
            targets: ["MusicFeature"]
        ),
    ],
    dependencies: [
        .package(path: "../AuralisPrimaryModels"),
        .package(path: "../AuraUI"),
    ],
    targets: [
        .target(
            name: "MusicFeature",
            dependencies: [
                "AuralisPrimaryModels",
                "AuraUI",
            ]
        ),
        .testTarget(
            name: "MusicFeatureTests",
            dependencies: ["MusicFeature"]
        ),
    ]
)
